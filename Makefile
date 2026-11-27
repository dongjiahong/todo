.DEFAULT_GOAL := help
.PHONY: help core core-macos core-android macos-bin macos macos-app run-macos \
        android android-debug android-release install-android release clean

GO ?= /usr/local/go/bin/go
GOPATH_BIN := $(shell $(GO) env GOPATH)/bin
GOMOBILE ?= $(shell command -v gomobile 2>/dev/null || echo "$(GOPATH_BIN)/gomobile")
APP_NAME := TODO
VERSION ?= 0.2.0
BUILD_NUM ?= 20

MAC_LIB_DIR := macos/Lib
ANDROID_LIBS_DIR := android/app/libs
GRADLE := $(shell if [ -x android/gradlew ]; then echo "./gradlew"; else echo "gradle"; fi)

# Prefer an SDK that does not require Xcode-only SwiftUIMacros plugin when using CommandLineTools
MAC_SDK := $(shell \
	for p in \
		/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
		/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk \
		/Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk; do \
		if [ -d "$$p" ]; then echo "$$p"; exit 0; fi; \
	done; \
	xcrun --show-sdk-path)

help: ## 显示所有可用命令与说明
	@printf "\n\033[1m领航 Navigator 构建与发版命令\033[0m\n\n"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n示例：\n  make macos-app\n  make android-debug\n  make release v=0.2.0\n\n"

core: core-macos core-android ## 同时编译 macOS 静态库与 Android AAR

core-macos: ## 编译 Go Core 为 macOS 静态库 (arm64)
	mkdir -p $(MAC_LIB_DIR)
	cd core && $(GO) mod tidy && CGO_ENABLED=1 CGO_CFLAGS="-mmacosx-version-min=14.0" $(GO) build -buildmode=c-archive -o ../$(MAC_LIB_DIR)/libnavigator_core.a ./bridge/cgo

core-android: ## 编译 Go Core 为 Android AAR (arm64-v8a)
	mkdir -p $(ANDROID_LIBS_DIR)
	cd core && $(GO) get golang.org/x/mobile/bind && $(GO) mod tidy && PATH="$(GOPATH_BIN):$$PATH" "$(GOMOBILE)" bind -target=android/arm64 -androidapi=28 -o ../$(ANDROID_LIBS_DIR)/navigator-core.aar ./bridge/mobile

macos-bin: ## 仅重新编译 SwiftUI 二进制（复用已有 libnavigator_core.a）
	mkdir -p build/bin
	swiftc -O -parse-as-library \
		-sdk "$(MAC_SDK)" \
		-target arm64-apple-macosx14.0 \
		-I macos/Sources/CNavigatorCore \
		macos/Sources/Navigator/*.swift \
		-L $(MAC_LIB_DIR) -lnavigator_core \
		-framework CoreFoundation -framework Security -framework UserNotifications -framework AppKit -framework SwiftUI \
		-lresolv \
		-o build/bin/$(APP_NAME)

icons: ## 从源图生成 macOS .icns 与 Android mipmap 图标（默认根目录 icon.png，可用 ICON= 指定）
	scripts/make-icons.sh "$(ICON)"

macos: core-macos macos-bin ## 编译 Go Core + macOS SwiftUI 二进制

macos-app: macos ## 打包 macOS build/TODO.app（含 AppIcon.icns）
	mkdir -p build/$(APP_NAME).app/Contents/MacOS build/$(APP_NAME).app/Contents/Resources
	cp build/bin/$(APP_NAME) build/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)
	if [ -f macos/Resources/AppIcon.icns ]; then cp macos/Resources/AppIcon.icns build/$(APP_NAME).app/Contents/Resources/AppIcon.icns; fi
	printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>\n<key>CFBundleExecutable</key><string>$(APP_NAME)</string>\n<key>CFBundleIdentifier</key><string>com.lele.todo</string>\n<key>CFBundleName</key><string>TODO</string>\n<key>CFBundleDisplayName</key><string>TODO</string>\n<key>CFBundleIconFile</key><string>AppIcon</string>\n<key>CFBundlePackageType</key><string>APPL</string>\n<key>CFBundleShortVersionString</key><string>$(VERSION)</string>\n<key>CFBundleVersion</key><string>$(BUILD_NUM)</string>\n<key>LSMinimumSystemVersion</key><string>14.0</string>\n<key>NSHighResolutionCapable</key><true/>\n</dict></plist>\n' > build/$(APP_NAME).app/Contents/Info.plist
	@echo "Built build/$(APP_NAME).app"

run-macos: macos-app ## 编译并启动 macOS Navigator.app
	open build/$(APP_NAME).app

android-debug: core-android ## 编译 Android Debug APK（可直接 adb 安装调试）
	cd android && $(GRADLE) assembleDebug
	@echo "Built android/app/build/outputs/apk/debug/app-debug.apk"

android-release: core-android ## 编译 Android Release APK
	cd android && $(GRADLE) assembleRelease
	@echo "Built android/app/build/outputs/apk/release/"

android: android-release ## 编译 Android Release APK（android-release 别名）

install-android: android-debug ## 编译并通过 adb 安装 Debug APK 到已连接手机
	adb install -r android/app/build/outputs/apk/debug/app-debug.apk

release: ## 打包双端发版产物（用法：make release v=0.2.0）
	@if [ -z "$(v)" ]; then echo "Usage: make release v=0.2.0"; exit 1; fi
	$(MAKE) macos-app VERSION=$(v)
	$(MAKE) android-debug
	mkdir -p build/release
	hdiutil create -volname "$(APP_NAME)" -srcfolder build/$(APP_NAME).app -ov -format UDZO build/release/$(APP_NAME)-$(v)-macos-arm64.dmg
	cp android/app/build/outputs/apk/debug/app-debug.apk build/release/$(APP_NAME)-$(v)-android-arm64.apk
	@echo ""
	@echo "Release 产物已就绪：build/release/"
	@ls -lh build/release/
	@echo ""
	@echo "如需发布 GitHub Release，可执行："
	@echo "  git tag v$(v) && git push origin v$(v)"
	@echo "  gh release create v$(v) build/release/$(APP_NAME)-$(v)-macos-arm64.dmg build/release/$(APP_NAME)-$(v)-android-arm64.apk --title \"Navigator v$(v)\""

clean: ## 清理所有编译产物与缓存
	rm -rf build $(MAC_LIB_DIR) macos/.build android/app/build
