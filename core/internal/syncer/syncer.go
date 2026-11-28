package syncer

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"navigator/core/internal/model"
	"navigator/core/internal/store"
)

const (
	DiscoveryPort = 8788
	DefaultPort   = 8787
	pairingTTLMs  = 5 * 60 * 1000
	peerStaleMs   = 16 * 1000
	beaconEvery   = 3 * time.Second
	clockMarginMs = 5 * 60 * 1000
	exchangeWait  = 5 * time.Second
)

type udpBeacon struct {
	App        string `json:"app"`
	V          int    `json:"v"`
	DeviceID   string `json:"deviceId"`
	DeviceName string `json:"deviceName"`
	HTTPPort   int    `json:"httpPort"`
}

type pairReq struct {
	DeviceID   string `json:"deviceId"`
	DeviceName string `json:"deviceName"`
	Code       string `json:"code"`
	HTTPPort   int    `json:"httpPort"`
}

type pairResp struct {
	DeviceID      string `json:"deviceId"`
	DeviceName    string `json:"deviceName"`
	PairingSecret string `json:"pairingSecret"`
}

type exchangeReq struct {
	Tasks []model.Task     `json:"tasks"`
	Tags  []model.Tag      `json:"tags"`
	Lists []model.TaskList `json:"lists,omitempty"`
	Since int64            `json:"since"`
}

type exchangeResp struct {
	Tasks []model.Task     `json:"tasks"`
	Tags  []model.Tag      `json:"tags"`
	Lists []model.TaskList `json:"lists,omitempty"`
	At    int64            `json:"at"`
}

// Syncer implements TradeFlow-style symmetric P2P LAN discovery, one-time 6-digit pairing,
// persistent HMAC-SHA256 peer secrets, and event-driven bidirectional sync on both macOS and Android.
type Syncer struct {
	store *store.Store

	mu          sync.Mutex
	deviceID    string
	deviceName  string
	running     bool
	boundPort   int
	pairingCode string
	pairingExp  int64
	discovered  map[string]model.DiscoveredPeer
	peerSecrets map[string]string
	peerHeard   map[string]int64
	peerAssets  map[string]map[string]struct{}
	syncedAt    int64
	lastError   string
	listener    func(string)

	nudgeCh     chan struct{}
	stopCh      chan struct{}
	started     atomic.Bool
	syncInFlight atomic.Bool
}

func New(st *store.Store, deviceID, deviceName string) *Syncer {
	s := &Syncer{
		store:       st,
		deviceID:    deviceID,
		deviceName:  deviceName,
		discovered:  make(map[string]model.DiscoveredPeer),
		peerSecrets: make(map[string]string),
		peerHeard:   make(map[string]int64),
		peerAssets:  make(map[string]map[string]struct{}),
		nudgeCh:     make(chan struct{}, 1),
		stopCh:      make(chan struct{}),
	}
	s.reloadPeerSecrets()
	return s
}

func (s *Syncer) reloadPeerSecrets() {
	peers, err := s.store.ListSyncPeers()
	if err != nil {
		return
	}
	s.mu.Lock()
	s.peerSecrets = make(map[string]string, len(peers))
	for _, p := range peers {
		s.peerSecrets[p.DeviceID] = p.PairingSecret
	}
	s.mu.Unlock()
}

func (s *Syncer) SetListener(fn func(string)) {
	s.mu.Lock()
	s.listener = fn
	s.mu.Unlock()
}

// Start launches the symmetric HTTP sync server, UDP beacon broadcaster/listener, and event-driven sync loop.
func (s *Syncer) Start(port int) (model.SyncStatus, error) {
	if !s.started.CompareAndSwap(false, true) {
		return s.Status(), nil
	}
	if port <= 0 {
		port = DefaultPort
	}
	ln, err := net.Listen("tcp4", fmt.Sprintf("0.0.0.0:%d", port))
	if err != nil {
		ln, err = net.Listen("tcp4", "0.0.0.0:0")
		if err != nil {
			s.started.Store(false)
			return s.Status(), err
		}
	}
	bound := ln.Addr().(*net.TCPAddr).Port
	s.mu.Lock()
	s.running = true
	s.boundPort = bound
	s.mu.Unlock()

	mux := http.NewServeMux()
	mux.HandleFunc("/sync/ping", s.handlePing)
	mux.HandleFunc("/sync/pair", s.handlePair)
	mux.HandleFunc("/state", s.handleState)
	mux.HandleFunc("/assets/", s.handleAsset)

	srv := &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() { _ = srv.Serve(ln) }()
	go s.runUDPDiscovery(bound)
	go s.eventDrivenLoop()

	// Initial startup sync after 1.5s
	go func() {
		time.Sleep(1500 * time.Millisecond)
		s.Nudge()
	}()

	s.emitStatus()
	return s.Status(), nil
}

// GeneratePairingCode creates a 6-digit one-time pairing code valid for 5 minutes.
func (s *Syncer) GeneratePairingCode() (string, int64, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		return "", 0, err
	}
	code := fmt.Sprintf("%06d", n.Int64()+100000)
	exp := time.Now().UnixMilli() + pairingTTLMs
	s.mu.Lock()
	s.pairingCode = code
	s.pairingExp = exp
	s.lastError = ""
	s.mu.Unlock()
	s.emitStatus()
	return code, exp, nil
}

// PairWithPeer exchanges a 6-digit code with a peer at ip:port and persists the shared HMAC secret.
func (s *Syncer) PairWithPeer(rawIP string, port int, code string) (model.PairedPeer, error) {
	ip, parsedPort := splitHostPortDefault(rawIP, port)
	if ip == "" {
		return model.PairedPeer{}, fmt.Errorf("请输入有效的局域网 IP")
	}
	cleanCode := strings.TrimSpace(code)
	if len(cleanCode) != 6 {
		return model.PairedPeer{}, fmt.Errorf("请输入 6 位数字配对码")
	}

	s.mu.Lock()
	myID := s.deviceID
	myName := s.deviceName
	myPort := s.boundPort
	s.mu.Unlock()
	if myPort == 0 {
		myPort = DefaultPort
	}

	payload, _ := json.Marshal(pairReq{
		DeviceID:   myID,
		DeviceName: myName,
		Code:       cleanCode,
		HTTPPort:   myPort,
	})
	client := &http.Client{Timeout: exchangeWait}
	url := fmt.Sprintf("http://%s:%d/sync/pair", ip, parsedPort)
	resp, err := client.Post(url, "application/json", bytes.NewReader(payload))
	if err != nil {
		return model.PairedPeer{}, fmt.Errorf("无法连接 %s:%d（请确认同一 Wi-Fi）", ip, parsedPort)
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		msg := strings.TrimSpace(string(bodyBytes))
		if msg == "" {
			msg = fmt.Sprintf("配对失败 (%d)", resp.StatusCode)
		}
		return model.PairedPeer{}, fmt.Errorf("%s", msg)
	}

	var pr pairResp
	if err := json.Unmarshal(bodyBytes, &pr); err != nil || pr.DeviceID == "" || pr.PairingSecret == "" {
		return model.PairedPeer{}, fmt.Errorf("解析配对响应失败")
	}

	peer := model.PairedPeer{
		DeviceID:      pr.DeviceID,
		DeviceName:    pr.DeviceName,
		PairingSecret: pr.PairingSecret,
		LastIP:        ip,
		LastPort:      parsedPort,
		Online:        true,
	}
	if err := s.store.UpsertSyncPeer(peer); err != nil {
		return model.PairedPeer{}, err
	}
	s.mu.Lock()
	s.peerSecrets[peer.DeviceID] = peer.PairingSecret
	s.lastError = ""
	s.mu.Unlock()
	s.emitStatus()

	// Trigger immediate bidirectional sync right after pairing
	go func() {
		time.Sleep(300 * time.Millisecond)
		_ = s.SyncPeerByID(peer.DeviceID)
	}()
	return peer, nil
}

// DeletePairedPeer unpairs a device and removes its secret.
func (s *Syncer) DeletePairedPeer(deviceID string) error {
	if err := s.store.DeleteSyncPeer(deviceID); err != nil {
		return err
	}
	s.mu.Lock()
	delete(s.peerSecrets, deviceID)
	delete(s.peerHeard, deviceID)
	s.mu.Unlock()
	s.emitStatus()
	return nil
}

// Nudge schedules an immediate debounced sync across online paired peers.
func (s *Syncer) Nudge() {
	select {
	case s.nudgeCh <- struct{}{}:
	default:
	}
}

// SyncAllPaired synchronizes with all reachable paired peers once.
func (s *Syncer) SyncAllPaired() error {
	if !s.syncInFlight.CompareAndSwap(false, true) {
		return nil
	}
	defer s.syncInFlight.Store(false)

	peers, err := s.store.ListSyncPeers()
	if err != nil || len(peers) == 0 {
		return err
	}
	var lastErr error
	for _, p := range peers {
		if err := s.syncSinglePeer(p); err != nil {
			lastErr = err
		}
	}
	return lastErr
}

// SyncPeerByID synchronizes with a specific paired device immediately.
func (s *Syncer) SyncPeerByID(deviceID string) error {
	peers, err := s.store.ListSyncPeers()
	if err != nil {
		return err
	}
	for _, p := range peers {
		if p.DeviceID == deviceID {
			if err := s.syncSinglePeer(p); err != nil {
				s.mu.Lock()
				s.lastError = err.Error()
				s.mu.Unlock()
				s.emitStatus()
				return err
			}
			return nil
		}
	}
	return fmt.Errorf("未找到该已配对设备")
}

func (s *Syncer) Status() model.SyncStatus {
	now := time.Now().UnixMilli()
	s.mu.Lock()
	for id, d := range s.discovered {
		if now-d.LastSeenMs > peerStaleMs {
			delete(s.discovered, id)
		}
	}
	activeCode := ""
	activeExp := int64(0)
	if s.pairingCode != "" && now <= s.pairingExp {
		activeCode = s.pairingCode
		activeExp = s.pairingExp
	} else {
		s.pairingCode = ""
		s.pairingExp = 0
	}

	discCopy := make(map[string]model.DiscoveredPeer, len(s.discovered))
	for k, v := range s.discovered {
		discCopy[k] = v
	}
	running := s.running
	port := s.boundPort
	devID := s.deviceID
	devName := s.deviceName
	syncedAt := s.syncedAt
	lastErr := s.lastError
	s.mu.Unlock()

	savedPeers, _ := s.store.ListSyncPeers()
	pairedSet := make(map[string]struct{}, len(savedPeers))
	pairedOut := make([]model.PairedPeer, 0, len(savedPeers))
	for _, p := range savedPeers {
		pairedSet[p.DeviceID] = struct{}{}
		if d, ok := discCopy[p.DeviceID]; ok {
			p.Online = true
			p.LastIP = d.IP
			p.LastPort = d.HTTPPort
		} else {
			p.Online = false
		}
		pairedOut = append(pairedOut, p)
	}

	unpairedDisc := make([]model.DiscoveredPeer, 0, len(discCopy))
	for id, d := range discCopy {
		if _, isPaired := pairedSet[id]; !isPaired {
			unpairedDisc = append(unpairedDisc, d)
		}
	}

	addr := ""
	if port > 0 {
		addr = fmt.Sprintf("%s:%d", lanIP(), port)
	}

	return model.SyncStatus{
		Running:           running,
		DeviceID:          devID,
		DeviceName:        devName,
		Address:           addr,
		HTTPPort:          port,
		ActivePairingCode: activeCode,
		PairingExpiresAt:  activeExp,
		PairedPeers:       pairedOut,
		DiscoveredPeers:   unpairedDisc,
		SyncedAt:          syncedAt,
		LastError:         lastErr,
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

// MARK: - HTTP Handlers

func (s *Syncer) handlePing(w http.ResponseWriter, _ *http.Request) {
	s.mu.Lock()
	id, name := s.deviceID, s.deviceName
	s.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"ok":         true,
		"deviceId":   id,
		"deviceName": name,
	})
}

func (s *Syncer) handlePair(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var req pairReq
	if err := json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&req); err != nil {
		http.Error(w, "无效的配对请求", http.StatusBadRequest)
		return
	}
	now := time.Now().UnixMilli()

	s.mu.Lock()
	valid := s.pairingCode != "" && now <= s.pairingExp && strings.TrimSpace(req.Code) == s.pairingCode
	if !valid {
		s.mu.Unlock()
		http.Error(w, "配对码错误或已过期", http.StatusForbidden)
		return
	}
	secret := randomHex(32)
	s.pairingCode = ""
	s.pairingExp = 0
	s.peerSecrets[req.DeviceID] = secret
	myID := s.deviceID
	myName := s.deviceName
	s.mu.Unlock()

	hostIP, _, _ := net.SplitHostPort(r.RemoteAddr)
	peerPort := req.HTTPPort
	if peerPort <= 0 {
		peerPort = DefaultPort
	}
	_ = s.store.UpsertSyncPeer(model.PairedPeer{
		DeviceID:      req.DeviceID,
		DeviceName:    req.DeviceName,
		PairingSecret: secret,
		LastIP:        hostIP,
		LastPort:      peerPort,
	})
	s.emitStatus()

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(pairResp{
		DeviceID:      myID,
		DeviceName:    myName,
		PairingSecret: secret,
	})

	go func() {
		time.Sleep(500 * time.Millisecond)
		s.Nudge()
	}()
}

func (s *Syncer) verifyHMAC(r *http.Request) (string, error) {
	devID := strings.TrimSpace(r.Header.Get("X-Todo-Device-Id"))
	tsStr := strings.TrimSpace(r.Header.Get("X-Todo-Timestamp"))
	sig := strings.TrimSpace(r.Header.Get("X-Todo-Signature"))
	if devID == "" || tsStr == "" || sig == "" {
		return "", fmt.Errorf("缺少签名头")
	}
	ts, err := strconv.ParseInt(tsStr, 10, 64)
	if err != nil {
		return "", fmt.Errorf("时间戳非法")
	}
	diff := time.Now().UnixMilli() - ts
	if diff < 0 {
		diff = -diff
	}
	if diff > 10*60*1000 {
		return "", fmt.Errorf("时钟偏差过大")
	}
	s.mu.Lock()
	secret := s.peerSecrets[devID]
	s.mu.Unlock()
	if secret == "" {
		return "", fmt.Errorf("设备尚未配对")
	}
	expected := signHMAC(secret, fmt.Sprintf("%s|%s|%s", r.Method, r.URL.RequestURI(), tsStr))
	if !hmac.Equal([]byte(strings.ToLower(expected)), []byte(strings.ToLower(sig))) {
		return "", fmt.Errorf("HMAC 签名校验失败")
	}
	return devID, nil
}

func (s *Syncer) handleState(w http.ResponseWriter, r *http.Request) {
	peerDevID, err := s.verifyHMAC(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var req exchangeReq
	if err := json.NewDecoder(io.LimitReader(r.Body, 8<<20)).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	mergedTasks, mergedTags, mergedLists, err := s.store.Upsert(req.Tasks, req.Tags, req.Lists)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	tasks, tags, lists, at, err := s.store.ChangesSince(req.Since)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	now := time.Now().UnixMilli()
	hostIP, _, _ := net.SplitHostPort(r.RemoteAddr)
	_ = s.store.UpdatePeerSyncMeta(peerDevID, hostIP, DefaultPort, now)

	s.mu.Lock()
	s.syncedAt = now
	s.lastError = ""
	s.mu.Unlock()

	if len(mergedTasks) > 0 || len(mergedTags) > 0 || len(mergedLists) > 0 {
		s.emit(model.SyncEvent{Type: "rows", Tasks: mergedTasks, Tags: mergedTags, Lists: mergedLists, At: at})
	}
	s.emitStatus()

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(exchangeResp{Tasks: tasks, Tags: tags, Lists: lists, At: at})
}

func (s *Syncer) handleAsset(w http.ResponseWriter, r *http.Request) {
	if _, err := s.verifyHMAC(r); err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
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

// MARK: - UDP Discovery (Broadcast + Listen, TradeFlow v2 style)

func (s *Syncer) runUDPDiscovery(httpPort int) {
	conn, err := net.ListenPacket("udp4", fmt.Sprintf("0.0.0.0:%d", DiscoveryPort))
	if err != nil {
		conn, err = net.ListenPacket("udp4", "0.0.0.0:0")
		if err != nil {
			return
		}
	}
	defer conn.Close()

	// Periodic beacon broadcaster (every 3s)
	go func() {
		ticker := time.NewTicker(beaconEvery)
		defer ticker.Stop()
		sendBeacon := func() {
			s.mu.Lock()
			b := udpBeacon{
				App:        "todo",
				V:          3,
				DeviceID:   s.deviceID,
				DeviceName: s.deviceName,
				HTTPPort:   httpPort,
			}
			s.mu.Unlock()
			raw, err := json.Marshal(b)
			if err != nil {
				return
			}
			for _, bcast := range broadcastAddresses() {
				_, _ = conn.WriteTo(raw, &net.UDPAddr{IP: bcast, Port: DiscoveryPort})
			}
			_, _ = conn.WriteTo(raw, &net.UDPAddr{IP: net.IPv4bcast, Port: DiscoveryPort})
		}
		sendBeacon()
		for {
			select {
			case <-ticker.C:
				sendBeacon()
			case <-s.stopCh:
				return
			}
		}
	}()

	// Beacon receiver loop
	buf := make([]byte, 1024)
	for {
		n, from, err := conn.ReadFrom(buf)
		if err != nil {
			return
		}
		var b udpBeacon
		if json.Unmarshal(buf[:n], &b) != nil || b.App != "todo" || b.V != 3 || b.DeviceID == "" {
			continue
		}
		udpFrom, ok := from.(*net.UDPAddr)
		if !ok {
			continue
		}
		ip4 := udpFrom.IP.To4()
		if ip4 == nil {
			continue
		}
		now := time.Now().UnixMilli()
		shouldTriggerSync := false
		shouldEmitStatus := false

		s.mu.Lock()
		if b.DeviceID == s.deviceID {
			s.mu.Unlock()
			continue
		}
		prev, existed := s.discovered[b.DeviceID]
		wasOffline := !existed || (now-prev.LastSeenMs > peerStaleMs)
		peer := model.DiscoveredPeer{
			DeviceID:   b.DeviceID,
			DeviceName: b.DeviceName,
			IP:         ip4.String(),
			HTTPPort:   b.HTTPPort,
			LastSeenMs: now,
		}
		s.discovered[b.DeviceID] = peer
		if wasOffline || prev.IP != peer.IP || prev.HTTPPort != peer.HTTPPort {
			shouldEmitStatus = true
		}
		if wasOffline && s.peerSecrets[b.DeviceID] != "" {
			shouldTriggerSync = true
		}
		s.mu.Unlock()

		if shouldEmitStatus {
			s.emitStatus()
		}
		if shouldTriggerSync {
			s.Nudge()
		}
	}
}

// MARK: - Event-Driven Sync Loop (Zero wasteful polling)

func (s *Syncer) eventDrivenLoop() {
	for {
		select {
		case <-s.nudgeCh:
			// Debounce rapid local edits by 800ms
			time.Sleep(800 * time.Millisecond)
			select {
			case <-s.nudgeCh:
			default:
			}
			_ = s.SyncAllPaired()
		case <-s.stopCh:
			return
		}
	}
}

func (s *Syncer) syncSinglePeer(peer model.PairedPeer) error {
	s.mu.Lock()
	disc, isOnline := s.discovered[peer.DeviceID]
	myID := s.deviceID
	heard := s.peerHeard[peer.DeviceID]
	s.mu.Unlock()

	ip := peer.LastIP
	port := peer.LastPort
	if isOnline {
		ip = disc.IP
		port = disc.HTTPPort
	}
	if ip == "" {
		return fmt.Errorf("未找到 %s 的局域网地址", peer.DeviceName)
	}
	if port <= 0 {
		port = DefaultPort
	}

	since := heard - clockMarginMs
	if since < 0 {
		since = 0
	}
	tasks, tags, lists, _, err := s.store.ChangesSince(since)
	if err != nil {
		return err
	}

	addr := fmt.Sprintf("%s:%d", ip, port)
	body, _ := json.Marshal(exchangeReq{Tasks: tasks, Tags: tags, Lists: lists, Since: since})
	client := &http.Client{Timeout: exchangeWait}
	req, err := http.NewRequest(http.MethodPost, fmt.Sprintf("http://%s/state", addr), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	attachHMACHeaders(req, myID, peer.PairingSecret)

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("无法连接 %s (%s)", peer.DeviceName, addr)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized {
		return fmt.Errorf("%s 鉴权失败，请重新配对", peer.DeviceName)
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("同步失败 (%d)", resp.StatusCode)
	}

	var reply exchangeResp
	if err := json.NewDecoder(resp.Body).Decode(&reply); err != nil {
		return err
	}
	mergedTasks, mergedTags, mergedLists, err := s.store.Upsert(reply.Tasks, reply.Tags, reply.Lists)
	if err != nil {
		return err
	}

	s.syncMissingAssets(client, addr, myID, peer.PairingSecret, tasks, mergedTasks)

	now := time.Now().UnixMilli()
	_ = s.store.UpdatePeerSyncMeta(peer.DeviceID, ip, port, now)

	s.mu.Lock()
	if reply.At > s.peerHeard[peer.DeviceID] {
		s.peerHeard[peer.DeviceID] = reply.At
	}
	s.syncedAt = now
	s.lastError = ""
	s.mu.Unlock()

	if len(mergedTasks) > 0 || len(mergedTags) > 0 || len(mergedLists) > 0 {
		s.emit(model.SyncEvent{Type: "rows", Tasks: mergedTasks, Tags: mergedTags, Lists: mergedLists, At: reply.At})
	}
	s.emitStatus()
	return nil
}

func (s *Syncer) syncMissingAssets(client *http.Client, addr, myID, secret string, localTasks, remoteTasks []model.Task) {
	for _, t := range remoteTasks {
		for _, asset := range t.Attachments {
			if s.store.HasAsset(asset) {
				continue
			}
			req, err := http.NewRequest(http.MethodGet, fmt.Sprintf("http://%s/assets/%s", addr, asset), nil)
			if err != nil {
				continue
			}
			attachHMACHeaders(req, myID, secret)
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
	for _, t := range localTasks {
		for _, asset := range t.Attachments {
			if s.peerHasAsset(addr, asset) {
				continue
			}
			if headReq, err := http.NewRequest(http.MethodHead, fmt.Sprintf("http://%s/assets/%s", addr, asset), nil); err == nil {
				attachHMACHeaders(headReq, myID, secret)
				if headResp, err := client.Do(headReq); err == nil {
					headResp.Body.Close()
					if headResp.StatusCode == http.StatusOK {
						s.markPeerAsset(addr, asset)
						continue
					}
				}
			}
			data, err := s.store.ReadAsset(asset)
			if err != nil {
				continue
			}
			req, err := http.NewRequest(http.MethodPut, fmt.Sprintf("http://%s/assets/%s", addr, asset), bytes.NewReader(data))
			if err != nil {
				continue
			}
			attachHMACHeaders(req, myID, secret)
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

func attachHMACHeaders(req *http.Request, deviceID, secret string) {
	ts := strconv.FormatInt(time.Now().UnixMilli(), 10)
	sig := signHMAC(secret, fmt.Sprintf("%s|%s|%s", req.Method, req.URL.RequestURI(), ts))
	req.Header.Set("X-Todo-Device-Id", deviceID)
	req.Header.Set("X-Todo-Timestamp", ts)
	req.Header.Set("X-Todo-Signature", sig)
}

func signHMAC(secret, msg string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(msg))
	return hex.EncodeToString(mac.Sum(nil))
}

func randomHex(nBytes int) string {
	b := make([]byte, nBytes)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func splitHostPortDefault(raw string, fallbackPort int) (string, int) {
	s := strings.TrimSpace(raw)
	s = strings.TrimPrefix(s, "http://")
	s = strings.TrimPrefix(s, "https://")
	s = strings.TrimSuffix(s, "/")
	if s == "" {
		return "", fallbackPort
	}
	if fallbackPort <= 0 {
		fallbackPort = DefaultPort
	}
	if host, portStr, err := net.SplitHostPort(s); err == nil {
		if p, err := strconv.Atoi(portStr); err == nil && p > 0 {
			return host, p
		}
		return host, fallbackPort
	}
	return s, fallbackPort
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
			ipnet, ok := a.(*net.IPNet);
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
