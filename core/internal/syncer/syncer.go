package syncer

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"navigator/core/internal/auth"
	"navigator/core/internal/model"
	"navigator/core/internal/store"
)

const (
	DiscoveryPort = 8788
	DefaultPort   = 8787
	probeMsg      = "NAVIGATOR/2 DISCOVER"
	offerPrefix   = "NAVIGATOR/2 OFFER "
	clockMarginMs = 5 * 60 * 1000
	exchangeWait  = 4 * time.Second
)

type peerEntry struct {
	addr        string
	heard       int64
	ok          bool
	at          int64
	refused     bool
	lockedUntil int64
	typed       bool
}

type exchangeReq struct {
	Tasks []model.Task `json:"tasks"`
	Tags  []model.Tag  `json:"tags"`
	Since int64        `json:"since"`
}

type exchangeResp struct {
	Tasks []model.Task `json:"tasks"`
	Tags  []model.Tag  `json:"tags"`
	At    int64        `json:"at"`
}

// Syncer runs the LAN HTTP server (on macOS/desktop) and active event-driven peer exchange loop.
type Syncer struct {
	store   *store.Store
	pairing *auth.Pairing

	mu         sync.Mutex
	prover     string
	peers      []*peerEntry
	peerAssets map[string]map[string]struct{}
	listening  bool
	boundPort  int
	syncedAt   int64
	listener   func(string)

	nudgeCh chan struct{}
	stopCh  chan struct{}
	started atomic.Bool
	serving atomic.Bool
}

func New(st *store.Store) *Syncer {
	return &Syncer{
		store:      st,
		pairing:    auth.NewPairing(),
		peerAssets: make(map[string]map[string]struct{}),
		nudgeCh:    make(chan struct{}, 1),
		stopCh:     make(chan struct{}),
	}
}

func (s *Syncer) SetListener(fn func(string)) {
	s.mu.Lock()
	s.listener = fn
	s.mu.Unlock()
}

func (s *Syncer) SetHostCode(code string) error {
	if !auth.IsValidCode(code) {
		return fmt.Errorf("pairing code must be 6 digits")
	}
	s.pairing.SetCode(code)
	s.emitStatus()
	return nil
}

func (s *Syncer) NewHostCode() (string, error) {
	code, err := auth.NewCode()
	if err != nil {
		return "", err
	}
	s.pairing.SetCode(code)
	s.emitStatus()
	return code, nil
}

func (s *Syncer) HostCode() string {
	return s.pairing.Code()
}

func (s *Syncer) SetPeerCode(code string) error {
	code = strings.TrimSpace(code)
	if code != "" && !auth.IsValidCode(code) {
		return fmt.Errorf("pairing code must be 6 digits")
	}
	s.mu.Lock()
	s.prover = code
	for _, p := range s.peers {
		p.refused = false
		p.lockedUntil = 0
	}
	s.mu.Unlock()
	s.emitStatus()
	s.Nudge()
	return nil
}

func (s *Syncer) AddManualPeer(rawAddr string) {
	addr := normalizeAddr(rawAddr)
	if addr == "" {
		return
	}
	s.mu.Lock()
	found := false
	for _, p := range s.peers {
		if p.addr == addr {
			p.typed = true
			found = true
			break
		}
	}
	if !found {
		kept := s.peers[:0]
		for _, p := range s.peers {
			if !p.typed {
				kept = append(kept, p)
			}
		}
		s.peers = append(kept, &peerEntry{addr: addr, typed: true})
	}
	s.mu.Unlock()
	s.emitStatus()
	s.Nudge()
}

// Nudge wakes the active sync loop immediately after any local mutation or foreground resume.
func (s *Syncer) Nudge() {
	select {
	case s.nudgeCh <- struct{}{}:
	default:
	}
}

// StartServer starts the LAN HTTP sync server and UDP discovery responder (used on Mac).
func (s *Syncer) StartServer(port int) (int, error) {
	if !s.serving.CompareAndSwap(false, true) {
		s.mu.Lock()
		p := s.boundPort
		s.mu.Unlock()
		return p, nil
	}
	if port <= 0 {
		port = DefaultPort
	}
	ln, err := net.Listen("tcp4", fmt.Sprintf("0.0.0.0:%d", port))
	if err != nil {
		ln, err = net.Listen("tcp4", "0.0.0.0:0")
		if err != nil {
			s.serving.Store(false)
			return 0, err
		}
	}
	bound := ln.Addr().(*net.TCPAddr).Port
	s.mu.Lock()
	s.listening = true
	s.boundPort = bound
	s.mu.Unlock()

	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/challenge", s.handleChallenge)
	mux.HandleFunc("/state", s.handleState)
	mux.HandleFunc("/assets/", s.handleAsset)

	srv := &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() { _ = srv.Serve(ln) }()
	go s.serveDiscovery(bound)
	s.emitStatus()
	return bound, nil
}

// StartWatcher begins active LAN peer discovery and event-driven state exchange.
func (s *Syncer) StartWatcher() {
	if !s.started.CompareAndSwap(false, true) {
		return
	}
	go s.exchangeLoop()
}

func (s *Syncer) Address() string {
	s.mu.Lock()
	port := s.boundPort
	s.mu.Unlock()
	if port == 0 {
		return ""
	}
	return fmt.Sprintf("%s:%d", lanIP(), port)
}

func (s *Syncer) Status() model.SyncStatus {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now().UnixMilli()
	anyOK := false
	anyRefused := false
	var maxRetry int64
	peers := make([]model.PeerStatus, 0, len(s.peers))
	for _, p := range s.peers {
		if p.ok {
			anyOK = true
		}
		if p.refused {
			anyRefused = true
		}
		if p.lockedUntil > maxRetry {
			maxRetry = p.lockedUntil
		}
		state := "ok"
		var retry int64
		if p.refused {
			state = "wrong"
		} else if p.lockedUntil > now {
			state = "locked"
			retry = (p.lockedUntil - now + 999) / 1000
		}
		peers = append(peers, model.PeerStatus{
			Addr:  p.addr,
			OK:    p.ok,
			At:    p.at,
			Typed: p.typed,
			Pair:  state,
			Retry: retry,
		})
	}

	pair := "ok"
	var retrySec int64
	if s.prover == "" && !s.listening {
		pair = "need"
	} else if anyRefused && !anyOK {
		pair = "wrong"
	} else if maxRetry > now && !anyOK {
		pair = "locked"
		retrySec = (maxRetry - now + 999) / 1000
	}

	addr := ""
	if s.boundPort > 0 {
		addr = fmt.Sprintf("%s:%d", lanIP(), s.boundPort)
	}
	return model.SyncStatus{
		Listening:   s.listening,
		Address:     addr,
		PairCode:    s.pairing.Code(),
		Peers:       peers,
		Unreachable: len(s.peers) > 0 && !anyOK,
		SyncedAt:    s.syncedAt,
		Pair:        pair,
		Retry:       retrySec,
	}
}

func (s *Syncer) emit(ev model.SyncEvent) {
	s.mu.Lock()
	fn := s.listener
	s.mu.Unlock()
	if fn == nil {
		return
	}
	if raw, err := json.Marshal(ev); err == nil {
		fn(string(raw))
	}
}

func (s *Syncer) emitStatus() {
	st := s.Status()
	s.emit(model.SyncEvent{Type: "status", Status: &st})
}

func (s *Syncer) requireAuth(w http.ResponseWriter, r *http.Request) bool {
	verdict, left := s.pairing.Verify(r.Header.Get(auth.NonceHeader), r.Header.Get(auth.ProofHeader))
	switch verdict {
	case auth.VerdictOK:
		return true
	case auth.VerdictLocked:
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusTooManyRequests)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"error": "too many attempts",
			"retry": int64(left.Seconds()) + 1,
		})
		return false
	default:
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"unauthorized"}`))
		return false
	}
}

func (s *Syncer) handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"ok":true}`))
}

func (s *Syncer) handleChallenge(w http.ResponseWriter, _ *http.Request) {
	nonce, err := s.pairing.IssueNonce()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"nonce": nonce})
}

func (s *Syncer) handleState(w http.ResponseWriter, r *http.Request) {
	if !s.requireAuth(w, r) {
		return
	}
	switch r.Method {
	case http.MethodGet:
		since, _ := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)
		tasks, tags, at, err := s.store.ChangesSince(since)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(exchangeResp{Tasks: tasks, Tags: tags, At: at})

	case http.MethodPost:
		var req exchangeReq
		if err := json.NewDecoder(io.LimitReader(r.Body, 8<<20)).Decode(&req); err != nil {
			http.Error(w, "invalid json", http.StatusBadRequest)
			return
		}
		mergedTasks, mergedTags, err := s.store.Upsert(req.Tasks, req.Tags)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		tasks, tags, at, err := s.store.ChangesSince(req.Since)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		if len(mergedTasks) > 0 || len(mergedTags) > 0 {
			s.mu.Lock()
			s.syncedAt = time.Now().UnixMilli()
			s.mu.Unlock()
			s.emit(model.SyncEvent{Type: "rows", Tasks: mergedTasks, Tags: mergedTags, At: at})
			s.emitStatus()
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(exchangeResp{Tasks: tasks, Tags: tags, At: at})

	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (s *Syncer) handleAsset(w http.ResponseWriter, r *http.Request) {
	if !s.requireAuth(w, r) {
		return
	}
	name := strings.TrimPrefix(r.URL.Path, "/assets/")
	if name == "" || strings.Contains(name, "/") || strings.Contains(name, "..") {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	switch r.Method {
	case http.MethodHead:
		if !s.store.HasAsset(name) {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusOK)
	case http.MethodGet:
		data, err := s.store.ReadAsset(name)
		if err != nil {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		_, _ = w.Write(data)
	case http.MethodPut:
		data, err := io.ReadAll(io.LimitReader(r.Body, 10<<20))
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		if err := s.store.WriteAssetRaw(name, data); err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (s *Syncer) serveDiscovery(port int) {
	conn, err := net.ListenPacket("udp4", fmt.Sprintf("0.0.0.0:%d", DiscoveryPort))
	if err != nil {
		return
	}
	defer conn.Close()
	buf := make([]byte, 512)
	reply := []byte(fmt.Sprintf("%s%d", offerPrefix, port))
	for {
		n, addr, err := conn.ReadFrom(buf)
		if err != nil {
			return
		}
		if string(buf[:n]) == probeMsg {
			_, _ = conn.WriteTo(reply, addr)
		}
	}
}

func (s *Syncer) discoverPeers() []string {
	conn, err := net.ListenPacket("udp4", "0.0.0.0:0")
	if err != nil {
		return nil
	}
	defer conn.Close()

	for _, bcast := range broadcastAddresses() {
		_, _ = conn.WriteTo([]byte(probeMsg), &net.UDPAddr{IP: bcast, Port: DiscoveryPort})
	}
	_, _ = conn.WriteTo([]byte(probeMsg), &net.UDPAddr{IP: net.IPv4bcast, Port: DiscoveryPort})

	deadline := time.Now().Add(650 * time.Millisecond)
	_ = conn.SetReadDeadline(deadline)
	buf := make([]byte, 512)
	seen := map[string]struct{}{}
	var out []string
	for {
		n, from, err := conn.ReadFrom(buf)
		if err != nil {
			break
		}
		text := strings.TrimSpace(string(buf[:n]))
		if !strings.HasPrefix(text, offerPrefix) {
			continue
		}
		port, err := strconv.Atoi(strings.TrimPrefix(text, offerPrefix))
		if err != nil || port <= 0 || port > 65535 {
			continue
		}
		udpFrom, ok := from.(*net.UDPAddr)
		if !ok {
			continue
		}
		ip4 := udpFrom.IP.To4()
		if ip4 == nil || s.isSelf(ip4, port) {
			continue
		}
		addr := fmt.Sprintf("%s:%d", ip4.String(), port)
		if _, dup := seen[addr]; !dup {
			seen[addr] = struct{}{}
			out = append(out, addr)
		}
	}
	return out
}

func (s *Syncer) isSelf(ip net.IP, port int) bool {
	s.mu.Lock()
	bound := s.boundPort
	s.mu.Unlock()
	if bound == 0 || bound != port {
		return false
	}
	for _, local := range localIPv4s() {
		if local.Equal(ip) {
			return true
		}
	}
	return false
}

func (s *Syncer) exchangeLoop() {
	client := &http.Client{Timeout: exchangeWait}
	lastProbe := time.Time{}
	missed := 0

	for {
		s.mu.Lock()
		code := s.prover
		peerCount := len(s.peers)
		s.mu.Unlock()

		if code == "" {
			s.waitNext(2 * time.Second)
			continue
		}

		if peerCount == 0 || time.Since(lastProbe) > 15*time.Second {
			found := s.discoverPeers()
			lastProbe = time.Now()
			if len(found) > 0 {
				s.mergeDiscovered(found)
			}
		}

		s.mu.Lock()
		targets := make([]*peerEntry, len(s.peers))
		copy(targets, s.peers)
		s.mu.Unlock()

		if len(targets) == 0 {
			missed++
			s.waitNext(backoff(missed))
			continue
		}

		anyOK := false
		for _, peer := range targets {
			now := time.Now().UnixMilli()
			s.mu.Lock()
			skip := peer.refused || peer.lockedUntil > now
			since := peer.heard - clockMarginMs
			if since < 0 {
				since = 0
			}
			s.mu.Unlock()
			if skip {
				continue
			}

			ok := s.syncWithPeer(client, peer, code, since)
			if ok {
				anyOK = true
			}
		}

		if anyOK {
			missed = 0
			s.waitNext(4 * time.Second)
		} else {
			missed++
			lastProbe = time.Time{}
			s.waitNext(backoff(missed))
		}
	}
}

func (s *Syncer) syncWithPeer(client *http.Client, peer *peerEntry, code string, since int64) bool {
	tasks, tags, _, err := s.store.ChangesSince(since)
	if err != nil {
		return false
	}
	nonce, err := fetchNonce(client, peer.addr)
	if err != nil {
		s.markLost(peer)
		return false
	}
	body, _ := json.Marshal(exchangeReq{Tasks: tasks, Tags: tags, Since: since})
	req, err := http.NewRequest(http.MethodPost, fmt.Sprintf("http://%s/state", peer.addr), bytes.NewReader(body))
	if err != nil {
		return false
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set(auth.NonceHeader, nonce)
	req.Header.Set(auth.ProofHeader, auth.Proof(code, nonce))

	resp, err := client.Do(req)
	if err != nil {
		s.markLost(peer)
		return false
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized {
		s.mu.Lock()
		peer.ok = false
		peer.refused = true
		s.mu.Unlock()
		s.emitStatus()
		return false
	}
	if resp.StatusCode == http.StatusTooManyRequests {
		var bodyMap map[string]any
		_ = json.NewDecoder(resp.Body).Decode(&bodyMap)
		retry := int64(60)
		if v, ok := bodyMap["retry"].(float64); ok && v > 0 {
			retry = int64(v)
		}
		s.mu.Lock()
		peer.ok = false
		peer.lockedUntil = time.Now().UnixMilli() + retry*1000
		s.mu.Unlock()
		s.emitStatus()
		return false
	}
	if resp.StatusCode != http.StatusOK {
		s.markLost(peer)
		return false
	}

	var reply exchangeResp
	if err := json.NewDecoder(resp.Body).Decode(&reply); err != nil {
		return false
	}
	mergedTasks, mergedTags, err := s.store.Upsert(reply.Tasks, reply.Tags)
	if err != nil {
		return false
	}

	// Sync missing attachment assets referenced by incoming or outgoing tasks.
	s.syncMissingAssets(client, peer.addr, code, tasks, mergedTasks)

	now := time.Now().UnixMilli()
	s.mu.Lock()
	if reply.At > peer.heard {
		peer.heard = reply.At
	}
	peer.ok = true
	peer.at = now
	peer.refused = false
	peer.lockedUntil = 0
	s.syncedAt = now
	s.mu.Unlock()

	if len(mergedTasks) > 0 || len(mergedTags) > 0 {
		s.emit(model.SyncEvent{Type: "rows", Tasks: mergedTasks, Tags: mergedTags, At: reply.At})
	}
	s.emitStatus()
	return true
}

func (s *Syncer) syncMissingAssets(client *http.Client, addr, code string, localTasks, remoteTasks []model.Task) {
	// Download remote assets we don't have yet
	for _, t := range remoteTasks {
		for _, asset := range t.Attachments {
			if s.store.HasAsset(asset) {
				continue
			}
			nonce, err := fetchNonce(client, addr)
			if err != nil {
				continue
			}
			req, err := http.NewRequest(http.MethodGet, fmt.Sprintf("http://%s/assets/%s", addr, asset), nil)
			if err != nil {
				continue
			}
			req.Header.Set(auth.NonceHeader, nonce)
			req.Header.Set(auth.ProofHeader, auth.Proof(code, nonce))
			resp, err := client.Do(req)
			if err == nil && resp.StatusCode == http.StatusOK {
				if data, err := io.ReadAll(io.LimitReader(resp.Body, 10<<20)); err == nil {
					_ = s.store.WriteAssetRaw(asset, data)
				}
			}
			if resp != nil {
				resp.Body.Close()
			}
		}
	}
	// Upload local assets referenced by recently updated tasks (skip if peer already has them)
	for _, t := range localTasks {
		for _, asset := range t.Attachments {
			if s.peerHasAsset(addr, asset) {
				continue
			}
			// Check with lightweight HEAD before transferring binary payload
			if nonce, err := fetchNonce(client, addr); err == nil {
				if headReq, err := http.NewRequest(http.MethodHead, fmt.Sprintf("http://%s/assets/%s", addr, asset), nil); err == nil {
					headReq.Header.Set(auth.NonceHeader, nonce)
					headReq.Header.Set(auth.ProofHeader, auth.Proof(code, nonce))
					if headResp, err := client.Do(headReq); err == nil {
						headResp.Body.Close()
						if headResp.StatusCode == http.StatusOK {
							s.markPeerAsset(addr, asset)
							continue
						}
					}
				}
			}
			data, err := s.store.ReadAsset(asset)
			if err != nil {
				continue
			}
			nonce, err := fetchNonce(client, addr)
			if err != nil {
				continue
			}
			req, err := http.NewRequest(http.MethodPut, fmt.Sprintf("http://%s/assets/%s", addr, asset), bytes.NewReader(data))
			if err != nil {
				continue
			}
			req.Header.Set(auth.NonceHeader, nonce)
			req.Header.Set(auth.ProofHeader, auth.Proof(code, nonce))
			if resp, err := client.Do(req); err == nil {
				if resp.StatusCode == http.StatusOK {
					s.markPeerAsset(addr, asset)
				}
				resp.Body.Close()
			}
		}
	}
}

func (s *Syncer) peerHasAsset(addr, name string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if set, ok := s.peerAssets[addr]; ok {
		_, exists := set[name]
		return exists
	}
	return false
}

func (s *Syncer) markPeerAsset(addr, name string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	set, ok := s.peerAssets[addr]
	if !ok {
		set = make(map[string]struct{})
		s.peerAssets[addr] = set
	}
	set[name] = struct{}{}
}

func fetchNonce(client *http.Client, addr string) (string, error) {
	resp, err := client.Get(fmt.Sprintf("http://%s/challenge", addr))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("challenge status %d", resp.StatusCode)
	}
	var out struct {
		Nonce string `json:"nonce"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil || out.Nonce == "" {
		return "", fmt.Errorf("bad challenge")
	}
	return out.Nonce, nil
}

func (s *Syncer) mergeDiscovered(addrs []string) {
	s.mu.Lock()
	changed := false
	for _, addr := range addrs {
		exists := false
		for _, p := range s.peers {
			if p.addr == addr {
				exists = true
				break
			}
		}
		if !exists {
			s.peers = append(s.peers, &peerEntry{addr: addr})
			changed = true
		}
	}
	s.mu.Unlock()
	if changed {
		s.emitStatus()
	}
}

func (s *Syncer) markLost(target *peerEntry) {
	s.mu.Lock()
	for i, p := range s.peers {
		if p == target {
			if p.typed {
				p.ok = false
			} else {
				s.peers = append(s.peers[:i], s.peers[i+1:]...)
			}
			break
		}
	}
	s.mu.Unlock()
	s.emitStatus()
}

func (s *Syncer) waitNext(d time.Duration) {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-s.nudgeCh:
	case <-t.C:
	case <-s.stopCh:
	}
}

func backoff(missed int) time.Duration {
	steps := []time.Duration{3 * time.Second, 6 * time.Second, 12 * time.Second, 24 * time.Second, 30 * time.Second}
	if missed <= 0 {
		return steps[0]
	}
	if missed >= len(steps) {
		return steps[len(steps)-1]
	}
	return steps[missed-1]
}

func normalizeAddr(raw string) string {
	s := strings.TrimSpace(raw)
	s = strings.TrimPrefix(s, "http://")
	s = strings.TrimPrefix(s, "https://")
	s = strings.TrimSuffix(s, "/")
	if s == "" {
		return ""
	}
	if !strings.Contains(s, ":") {
		return fmt.Sprintf("%s:%d", s, DefaultPort)
	}
	return s
}

func lanIP() string {
	conn, err := net.Dial("udp4", "1.1.1.1:80")
	if err == nil {
		defer conn.Close()
		if addr, ok := conn.LocalAddr().(*net.UDPAddr); ok && addr.IP != nil && !addr.IP.IsLoopback() {
			return addr.IP.String()
		}
	}
	for _, ip := range localIPv4s() {
		return ip.String()
	}
	return "127.0.0.1"
}

func localIPv4s() []net.IP {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	var out []net.IP
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			if ipnet, ok := a.(*net.IPNet); ok {
				if ip4 := ipnet.IP.To4(); ip4 != nil && !ip4.IsLoopback() {
					out = append(out, ip4)
				}
			}
		}
	}
	return out
}

func broadcastAddresses() []net.IP {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	var out []net.IP
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if !ok {
				continue
			}
			ip4 := ipnet.IP.To4()
			if ip4 == nil || len(ipnet.Mask) != 4 {
				continue
			}
			bcast := make(net.IP, 4)
			for i := 0; i < 4; i++ {
				bcast[i] = ip4[i] | ^ipnet.Mask[i]
			}
			out = append(out, bcast)
		}
	}
	return out
}
