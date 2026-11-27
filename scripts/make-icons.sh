#!/usr/bin/env bash
set -euo pipefail

# Default to root ./icon.png if present, else assets/icon.png
if [ -n "${1:-}" ]; then
  SRC="$1"
elif [ -f "icon.png" ]; then
  SRC="icon.png"
else
  SRC="assets/icon.png"
fi

if [ ! -f "$SRC" ]; then
  echo "Usage: $0 <path-to-icon.png>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$ROOT/build/.icon-tmp"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR" "$ROOT/macos/Resources"

# Composite onto a clean macOS HIG squircle icon canvas (1024x1024) with high-quality interpolation
MAC_MASTER="$TMP_DIR/mac_1024.png"
ANDROID_MASTER="$TMP_DIR/android_1024.png"

swift - "$SRC" "$MAC_MASTER" "$ANDROID_MASTER" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
let srcPath = args[1]
let macOut = args[2]
let androidOut = args[3]

guard let srcImg = NSImage(contentsOfFile: srcPath) else {
    fputs("Failed to load image: \(srcPath)\n", stderr)
    exit(1)
}

func renderIcon(size: Int, cornerRadius: CGFloat, padding: CGFloat, insetFraction: CGFloat, outPath: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .high

    let s = CGFloat(size)
    let cardRect = CGRect(x: padding, y: padding, width: s - padding * 2, height: s - padding * 2)
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Subtle elevation shadow for macOS squircle
    if padding > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.18).cgColor)
        ctx.addPath(cardPath)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Soft pearl gradient backdrop
    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()
    let colors = [
        NSColor(calibratedRed: 0.99, green: 0.995, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.93, green: 0.955, blue: 0.985, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    }

    // Draw source icon centered with balanced inset
    let inset = cardRect.width * insetFraction
    let drawRect = cardRect.insetBy(dx: inset, dy: inset)
    srcImg.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    ctx.restoreGState()

    // Subtle hairline border
    ctx.addPath(cardPath)
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.06).cgColor)
    ctx.setLineWidth(3)
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: outPath))
}

// macOS Big Sur/Sonoma HIG squircle (~10% outer margin, ~22% corner radius)
renderIcon(size: 1024, cornerRadius: 192, padding: 92, insetFraction: 0.16, outPath: macOut)
// Android full-bleed square/adaptive-friendly backdrop
renderIcon(size: 1024, cornerRadius: 0, padding: 0, insetFraction: 0.18, outPath: androidOut)
SWIFT

# 1. Generate macOS AppIcon.icns directly (standard PNG-in-ICNS chunks)
for px in 32 64 128 256 512 1024; do
  sips -s format png -z "$px" "$px" "$MAC_MASTER" --out "$TMP_DIR/${px}.png" >/dev/null
done

python3 - "$TMP_DIR" "$ROOT/macos/Resources/AppIcon.icns" <<'PY'
import struct, sys, os
tmp, out_path = sys.argv[1], sys.argv[2]
chunks = [
    (b"ic11", "32.png"),
    (b"ic12", "64.png"),
    (b"ic07", "128.png"),
    (b"ic08", "256.png"),
    (b"ic13", "256.png"),
    (b"ic09", "512.png"),
    (b"ic14", "512.png"),
    (b"ic10", "1024.png"),
]
body = bytearray()
for tag, fname in chunks:
    with open(os.path.join(tmp, fname), "rb") as f:
        data = f.read()
    body += tag + struct.pack(">I", len(data) + 8) + data
header = b"icns" + struct.pack(">I", len(body) + 8)
with open(out_path, "wb") as f:
    f.write(header + body)
PY

# 2. Generate Android mipmap launcher icons
RES="$ROOT/android/app/src/main/res"
for pair in "mdpi:48" "hdpi:72" "xhdpi:96" "xxhdpi:144" "xxxhdpi:192"; do
  density="${pair%%:*}"
  px="${pair##*:}"
  dir="$RES/mipmap-$density"
  mkdir -p "$dir"
  sips -s format png -z "$px" "$px" "$ANDROID_MASTER" --out "$dir/ic_launcher.png" >/dev/null
  cp "$dir/ic_launcher.png" "$dir/ic_launcher_round.png"
done

rm -rf "$TMP_DIR"
echo "Generated macos/Resources/AppIcon.icns and Android mipmap-* icons from $SRC"
