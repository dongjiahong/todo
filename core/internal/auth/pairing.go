package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"sync"
	"time"
)

const (
	NonceHeader = "X-Nav-Nonce"
	ProofHeader = "X-Nav-Proof"
	nonceTTL    = 30 * time.Second
	nonceMax    = 64
	failMax     = 5
	LockoutDur  = 60 * time.Second
)

type Verdict int

const (
	VerdictOK Verdict = iota
	VerdictUnauthorized
	VerdictLocked
)

// Pairing handles server-side 6-digit pairing code verification with one-time nonces and lockout.
type Pairing struct {
	mu          sync.Mutex
	code        string
	nonces      map[string]time.Time
	failures    int
	lockedUntil time.Time
}

func NewPairing() *Pairing {
	return &Pairing{
		nonces: make(map[string]time.Time),
	}
}

func IsValidCode(code string) bool {
	if len(code) != 6 {
		return false
	}
	for i := 0; i < 6; i++ {
		if code[i] < '0' || code[i] > '9' {
			return false
		}
	}
	return true
}

// NewCode generates a cryptographically uniform 6-digit code preserving leading zeros.
func NewCode() (string, error) {
	const limit = (^uint64(0) / 1_000_000) * 1_000_000
	var b [8]byte
	for {
		if _, err := rand.Read(b[:]); err != nil {
			return "", err
		}
		v := binary.LittleEndian.Uint64(b[:])
		if v < limit {
			return fmt.Sprintf("%06d", v%1_000_000), nil
		}
	}
}

func Proof(code, nonce string) string {
	mac := hmac.New(sha256.New, []byte(code))
	mac.Write([]byte(nonce))
	return hex.EncodeToString(mac.Sum(nil))
}

func (p *Pairing) SetCode(code string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.code = code
	p.nonces = make(map[string]time.Time)
	p.failures = 0
	p.lockedUntil = time.Time{}
}

func (p *Pairing) Code() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.code
}

func (p *Pairing) IssueNonce() (string, error) {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	nonce := hex.EncodeToString(raw[:])
	now := time.Now()

	p.mu.Lock()
	defer p.mu.Unlock()
	for k, exp := range p.nonces {
		if !exp.After(now) {
			delete(p.nonces, k)
		}
	}
	if len(p.nonces) >= nonceMax {
		var oldestKey string
		var oldestExp time.Time
		for k, exp := range p.nonces {
			if oldestKey == "" || exp.Before(oldestExp) {
				oldestKey = k
				oldestExp = exp
			}
		}
		if oldestKey != "" {
			delete(p.nonces, oldestKey)
		}
	}
	p.nonces[nonce] = now.Add(nonceTTL)
	return nonce, nil
}

func (p *Pairing) Verify(nonce, answer string) (Verdict, time.Duration) {
	now := time.Now()
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.lockedUntil.After(now) {
		return VerdictLocked, p.lockedUntil.Sub(now)
	}

	ok := false
	if p.code != "" && nonce != "" && answer != "" {
		if exp, exists := p.nonces[nonce]; exists {
			delete(p.nonces, nonce)
			if exp.After(now) {
				expected := Proof(p.code, nonce)
				ok = hmac.Equal([]byte(expected), []byte(answer))
			}
		}
	}

	if ok {
		p.failures = 0
		p.lockedUntil = time.Time{}
		return VerdictOK, 0
	}

	p.failures++
	if p.failures >= failMax {
		p.failures = 0
		p.lockedUntil = now.Add(LockoutDur)
		return VerdictLocked, LockoutDur
	}
	return VerdictUnauthorized, 0
}
