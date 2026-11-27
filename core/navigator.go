package core

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"navigator/core/internal/auth"
	"navigator/core/internal/model"
	"navigator/core/internal/store"
	"navigator/core/internal/syncer"
)

// Engine is the single entry point used by both macOS (CGo) and Android (gomobile).
type Engine struct {
	mu     sync.Mutex
	store  *store.Store
	syncer *syncer.Syncer
}

func Open(dataDir string) (*Engine, error) {
	st, err := store.Open(dataDir)
	if err != nil {
		return nil, err
	}
	sy := syncer.New(st)

	// Restore persisted pairing code for host or peer role.
	if hostCode := st.GetMeta("host_pair_code"); auth.IsValidCode(hostCode) {
		_ = sy.SetHostCode(hostCode)
	} else {
		if code, err := sy.NewHostCode(); err == nil {
			_ = st.SetMeta("host_pair_code", code)
		}
	}
	if peerCode := st.GetMeta("peer_pair_code"); auth.IsValidCode(peerCode) {
		_ = sy.SetPeerCode(peerCode)
	}
	if manualAddr := st.GetMeta("manual_peer_addr"); manualAddr != "" {
		sy.AddManualPeer(manualAddr)
	}

	eng := &Engine{store: st, syncer: sy}
	eng.seedIfFirstRun()
	_, _ = st.SnapshotDaily()
	go func() { _ = st.PruneOrphanAssets(24 * time.Hour) }()
	return eng, nil
}

func (e *Engine) Close() error {
	return e.store.Close()
}

func (e *Engine) SetEventListener(fn func(string)) {
	e.syncer.SetListener(fn)
}

func (e *Engine) LoadJSON() (string, error) {
	state, err := e.store.LoadAll()
	if err != nil {
		return "", err
	}
	raw, err := json.Marshal(state)
	return string(raw), err
}

func (e *Engine) SaveTaskJSON(taskJSON string) (string, error) {
	var t model.Task
	if err := json.Unmarshal([]byte(taskJSON), &t); err != nil {
		return "", err
	}
	now := time.Now().UnixMilli()
	if t.ID == "" {
		t.ID = newID("t")
	}
	if t.CreatedAt == 0 {
		t.CreatedAt = now
	}
	if t.UpdatedAt == 0 {
		t.UpdatedAt = now
	}
	t.Normalize()
	merged, _, err := e.store.Upsert([]model.Task{t}, nil)
	if err != nil {
		return "", err
	}
	e.syncer.Nudge()
	if len(merged) == 0 {
		return taskJSON, nil
	}
	raw, err := json.Marshal(merged[0])
	return string(raw), err
}

// CompleteTask toggles a task between done and todo.
// When completing a repeating task, automatically spawns the next occurrence in todo.
func (e *Engine) CompleteTask(taskID string, done bool) (string, error) {
	target, found, err := e.store.GetTask(taskID)
	if err != nil {
		return "", err
	}
	if !found {
		return "", fmt.Errorf("task not found: %s", taskID)
	}

	now := time.Now().UnixMilli()
	toSave := make([]model.Task, 0, 2)

	updated := target
	if done {
		updated.Status = model.StatusDone
		updated.CompletedAt = now
	} else {
		updated.Status = model.StatusTodo
		updated.CompletedAt = 0
	}
	updated.UpdatedAt = now
	if updated.Stamps == nil {
		updated.Stamps = map[string]int64{}
	}
	updated.Stamps["status"] = now
	updated.Stamps["completedAt"] = now
	toSave = append(toSave, updated)

	if done && target.RepeatRule != model.RepeatNone && target.DueAt != "" {
		nextDue := model.AdvanceDue(target.DueAt, target.RepeatRule)
		nextSubtasks := make([]model.Subtask, len(target.Subtasks))
		for i, st := range target.Subtasks {
			nextSubtasks[i] = model.Subtask{
				ID:    newID("s"),
				Title: st.Title,
				Done:  false,
				Order: i,
			}
		}
		next := model.Task{
			ID:         newID("t"),
			Title:      target.Title,
			Notes:      target.Notes,
			Status:     model.StatusTodo,
			Subtasks:   nextSubtasks,
			TagIDs:     append([]string(nil), target.TagIDs...),
			DueAt:      nextDue,
			RepeatRule: target.RepeatRule,
			Rank:       target.Rank + 1000,
			CreatedAt:  now,
			UpdatedAt:  now,
		}
		next.Normalize()
		toSave = append(toSave, next)
	}

	saved, _, err := e.store.Upsert(toSave, nil)
	if err != nil {
		return "", err
	}
	e.syncer.Nudge()
	raw, err := json.Marshal(saved)
	return string(raw), err
}

func (e *Engine) DeleteTask(taskID string, deleted bool) error {
	t, found, err := e.store.GetTask(taskID)
	if err != nil || !found {
		return err
	}
	now := time.Now().UnixMilli()
	t.Deleted = deleted
	t.UpdatedAt = now
	if t.Stamps == nil {
		t.Stamps = map[string]int64{}
	}
	t.Stamps["deleted"] = now
	_, _, err = e.store.Upsert([]model.Task{t}, nil)
	if err == nil {
		e.syncer.Nudge()
	}
	return err
}

func (e *Engine) SaveTagJSON(tagJSON string) (string, error) {
	var tag model.Tag
	if err := json.Unmarshal([]byte(tagJSON), &tag); err != nil {
		return "", err
	}
	if tag.ID == "" {
		tag.ID = newID("tag")
	}
	if tag.Hue == "" {
		tag.Hue = model.HueBlue
	}
	tag.UpdatedAt = time.Now().UnixMilli()
	_, saved, err := e.store.Upsert(nil, []model.Tag{tag})
	if err != nil {
		return "", err
	}
	e.syncer.Nudge()
	if len(saved) == 0 {
		return tagJSON, nil
	}
	raw, err := json.Marshal(saved[0])
	return string(raw), err
}

func (e *Engine) DeleteTag(tagID string) error {
	state, err := e.store.LoadAll()
	if err != nil {
		return err
	}
	now := time.Now().UnixMilli()
	var updatedTags []model.Tag
	for _, tg := range state.Tags {
		if tg.ID == tagID {
			tg.Deleted = true
			tg.UpdatedAt = now
			updatedTags = append(updatedTags, tg)
		}
	}
	var updatedTasks []model.Task
	for _, t := range state.Tasks {
		if t.Deleted {
			continue
		}
		kept := make([]string, 0, len(t.TagIDs))
		removed := false
		for _, id := range t.TagIDs {
			if id == tagID {
				removed = true
			} else {
				kept = append(kept, id)
			}
		}
		if removed {
			t.TagIDs = kept
			t.UpdatedAt = now
			if t.Stamps == nil {
				t.Stamps = map[string]int64{}
			}
			t.Stamps["tagIds"] = now
			updatedTasks = append(updatedTasks, t)
		}
	}
	_, _, err = e.store.Upsert(updatedTasks, updatedTags)
	if err == nil {
		e.syncer.Nudge()
	}
	return err
}

func (e *Engine) SaveAsset(data []byte, ext string) (string, error) {
	return e.store.SaveAsset(data, ext)
}

func (e *Engine) AssetPath(name string) string {
	return e.store.AssetPath(name)
}

// StartSync launches LAN discovery/exchange; if serve is true (macOS), also starts the LAN HTTP server.
func (e *Engine) StartSync(serve bool, port int) (string, error) {
	if serve {
		if _, err := e.syncer.StartServer(port); err != nil {
			return "", err
		}
	}
	e.syncer.StartWatcher()
	return e.SyncStatusJSON(), nil
}

func (e *Engine) HostPairCode() string {
	return e.syncer.HostCode()
}

func (e *Engine) RegeneratePairCode() (string, error) {
	code, err := e.syncer.NewHostCode()
	if err != nil {
		return "", err
	}
	_ = e.store.SetMeta("host_pair_code", code)
	return code, nil
}

func (e *Engine) SetPeerCode(code string) error {
	if err := e.syncer.SetPeerCode(code); err != nil {
		return err
	}
	_ = e.store.SetMeta("peer_pair_code", strings.TrimSpace(code))
	return nil
}

func (e *Engine) AddPeerAddress(addr string) {
	e.syncer.AddManualPeer(addr)
	_ = e.store.SetMeta("manual_peer_addr", strings.TrimSpace(addr))
}

func (e *Engine) SyncNow() {
	e.syncer.Nudge()
}

func (e *Engine) SyncStatusJSON() string {
	raw, _ := json.Marshal(e.syncer.Status())
	return string(raw)
}

func (e *Engine) ExportMarkdown() (string, error) {
	state, err := e.store.LoadAll()
	if err != nil {
		return "", err
	}
	tagMap := make(map[string]string, len(state.Tags))
	for _, tg := range state.Tags {
		if !tg.Deleted {
			tagMap[tg.ID] = tg.Label
		}
	}

	var b strings.Builder
	b.WriteString("# 领航 Navigator 导出\n\n")
	writeGroup := func(title string, status model.Status) {
		b.WriteString("## " + title + "\n\n")
		for _, t := range state.Tasks {
			if t.Deleted || t.Status != status {
				continue
			}
			mark := "[ ]"
			if t.Status == model.StatusDone {
				mark = "[x]"
			}
			b.WriteString(fmt.Sprintf("- %s **%s**", mark, t.Title))
			if t.DueAt != "" {
				b.WriteString(fmt.Sprintf(" (`%s`)", strings.ReplaceAll(t.DueAt, "T", " ")))
			}
			for _, tid := range t.TagIDs {
				if lbl, ok := tagMap[tid]; ok {
					b.WriteString(" #" + lbl)
				}
			}
			b.WriteString("\n")
			for _, st := range t.Subtasks {
				sm := "[ ]"
				if st.Done {
					sm = "[x]"
				}
				b.WriteString(fmt.Sprintf("  - %s %s\n", sm, st.Title))
			}
			if strings.TrimSpace(t.Notes) != "" {
				for _, line := range strings.Split(strings.TrimSpace(t.Notes), "\n") {
					b.WriteString("  > " + line + "\n")
				}
			}
		}
		b.WriteString("\n")
	}

	writeGroup("进行中", model.StatusDoing)
	writeGroup("待办", model.StatusTodo)
	writeGroup("日志簿（已完成）", model.StatusDone)
	return b.String(), nil
}

func (e *Engine) ImportJSON(raw string) error {
	var state model.BoardState
	if err := json.Unmarshal([]byte(raw), &state); err != nil {
		return err
	}
	_, _, err := e.store.Upsert(state.Tasks, state.Tags)
	if err == nil {
		e.syncer.Nudge()
	}
	return err
}

func (e *Engine) seedIfFirstRun() {
	state, err := e.store.LoadAll()
	if err != nil || state.Seeded {
		return
	}
	now := time.Now().UnixMilli()

	tags := []model.Tag{
		{ID: "work", Label: "工作", Hue: model.HueBlue, Order: 0, UpdatedAt: now},
		{ID: "personal", Label: "个人", Hue: model.HueGreen, Order: 1, UpdatedAt: now},
		{ID: "study", Label: "学习", Hue: model.HuePurple, Order: 2, UpdatedAt: now},
		{ID: "life", Label: "生活", Hue: model.HueAmber, Order: 3, UpdatedAt: now},
		{ID: "urgent", Label: "紧急", Hue: model.HueRed, Order: 4, UpdatedAt: now},
	}

	_, _, _ = e.store.Upsert(nil, tags)
}

func newID(prefix string) string {
	var b [6]byte
	_, _ = rand.Read(b[:])
	return fmt.Sprintf("%s_%s", prefix, hex.EncodeToString(b[:]))
}
