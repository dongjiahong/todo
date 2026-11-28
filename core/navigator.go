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
	eng.ensureDefaultListsAndMigrate()
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
	merged, _, _, err := e.store.Upsert([]model.Task{t}, nil, nil)
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
			ListID:     target.ListID,
			Flagged:    target.Flagged,
			Priority:   target.Priority,
			URL:        target.URL,
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

	saved, _, _, err := e.store.Upsert(toSave, nil, nil)
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
	_, _, _, err = e.store.Upsert([]model.Task{t}, nil, nil)
	if err == nil {
		e.syncer.Nudge()
	}
	return err
}

// ClearCompleted soft-deletes completed tasks (all if listID is empty, or only those in listID).
func (e *Engine) ClearCompleted(listID string) (string, error) {
	state, err := e.store.LoadAll()
	if err != nil {
		return "", err
	}
	now := time.Now().UnixMilli()
	var toUpdate []model.Task
	for _, t := range state.Tasks {
		if t.Deleted || t.Status != model.StatusDone {
			continue
		}
		if listID != "" && t.ListID != listID {
			continue
		}
		t.Deleted = true
		t.UpdatedAt = now
		if t.Stamps == nil {
			t.Stamps = map[string]int64{}
		}
		t.Stamps["deleted"] = now
		toUpdate = append(toUpdate, t)
	}
	if len(toUpdate) == 0 {
		return "[]", nil
	}
	saved, _, _, err := e.store.Upsert(toUpdate, nil, nil)
	if err != nil {
		return "", err
	}
	e.syncer.Nudge()
	raw, err := json.Marshal(saved)
	return string(raw), err
}

func (e *Engine) SaveListJSON(listJSON string) (string, error) {
	var list model.TaskList
	if err := json.Unmarshal([]byte(listJSON), &list); err != nil {
		return "", err
	}
	if list.ID == "" {
		list.ID = newID("list")
	}
	list.Normalize()
	list.UpdatedAt = time.Now().UnixMilli()
	_, _, saved, err := e.store.Upsert(nil, nil, []model.TaskList{list})
	if err != nil {
		return "", err
	}
	e.syncer.Nudge()
	if len(saved) == 0 {
		return listJSON, nil
	}
	raw, err := json.Marshal(saved[0])
	return string(raw), err
}

func (e *Engine) DeleteList(listID string) error {
	state, err := e.store.LoadAll()
	if err != nil {
		return err
	}
	now := time.Now().UnixMilli()
	var updatedLists []model.TaskList
	for _, l := range state.Lists {
		if l.ID == listID {
			l.Deleted = true
			l.UpdatedAt = now
			updatedLists = append(updatedLists, l)
		}
	}
	var updatedTasks []model.Task
	for _, t := range state.Tasks {
		if t.Deleted || t.ListID != listID {
			continue
		}
		t.Deleted = true
		t.UpdatedAt = now
		if t.Stamps == nil {
			t.Stamps = map[string]int64{}
		}
		t.Stamps["deleted"] = now
		updatedTasks = append(updatedTasks, t)
	}
	_, _, _, err = e.store.Upsert(updatedTasks, nil, updatedLists)
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
	_, saved, _, err := e.store.Upsert(nil, []model.Tag{tag}, nil)
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
	_, _, _, err = e.store.Upsert(updatedTasks, updatedTags, nil)
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

	writeTask := func(b *strings.Builder, t model.Task) {
		mark := "[ ]"
		if t.Status == model.StatusDone {
			mark = "[x]"
		}
		prio := ""
		switch t.Priority {
		case 1:
			prio = "! "
		case 2:
			prio = "!! "
		case 3:
			prio = "!!! "
		}
		b.WriteString(fmt.Sprintf("- %s %s**%s**", mark, prio, t.Title))
		if t.Flagged {
			b.WriteString(" 🚩")
		}
		if t.DueAt != "" {
			b.WriteString(fmt.Sprintf(" (`%s`)", strings.ReplaceAll(t.DueAt, "T", " ")))
		}
		for _, tid := range t.TagIDs {
			if lbl, ok := tagMap[tid]; ok {
				b.WriteString(" #" + lbl)
			}
		}
		b.WriteString("\n")
		if strings.TrimSpace(t.URL) != "" {
			b.WriteString(fmt.Sprintf("  - %s\n", strings.TrimSpace(t.URL)))
		}
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

	var b strings.Builder
	b.WriteString("# TODO 提醒事项导出\n\n")

	activeLists := make([]model.TaskList, 0, len(state.Lists))
	for _, l := range state.Lists {
		if !l.Deleted {
			activeLists = append(activeLists, l)
		}
	}
	for _, list := range activeLists {
		var listTasks []model.Task
		for _, t := range state.Tasks {
			if !t.Deleted && t.Status != model.StatusDone && t.ListID == list.ID {
				listTasks = append(listTasks, t)
			}
		}
		if len(listTasks) == 0 {
			continue
		}
		b.WriteString("## " + list.Name + "\n\n")
		for _, t := range listTasks {
			writeTask(&b, t)
		}
		b.WriteString("\n")
	}

	var doneTasks []model.Task
	for _, t := range state.Tasks {
		if !t.Deleted && t.Status == model.StatusDone {
			doneTasks = append(doneTasks, t)
		}
	}
	if len(doneTasks) > 0 {
		b.WriteString("## 已完成\n\n")
		for _, t := range doneTasks {
			writeTask(&b, t)
		}
		b.WriteString("\n")
	}
	return b.String(), nil
}

func (e *Engine) ImportJSON(raw string) error {
	var state model.BoardState
	if err := json.Unmarshal([]byte(raw), &state); err != nil {
		return err
	}
	_, _, _, err := e.store.Upsert(state.Tasks, state.Tags, state.Lists)
	if err == nil {
		e.syncer.Nudge()
	}
	return err
}

func (e *Engine) ensureDefaultListsAndMigrate() {
	state, err := e.store.LoadAll()
	if err != nil {
		return
	}
	now := time.Now().UnixMilli()

	// Ensure at least one default list ("提醒") exists.
	hasActiveList := false
	for _, l := range state.Lists {
		if !l.Deleted {
			hasActiveList = true
			break
		}
	}
	var seedLists []model.TaskList
	if !hasActiveList {
		seedLists = []model.TaskList{
			{ID: model.DefaultListID, Name: "提醒", Color: "orange", Icon: "list", Order: 0, UpdatedAt: now},
		}
	}

	var seedTags []model.Tag
	if !state.Seeded && len(state.Tags) == 0 {
		seedTags = []model.Tag{
			{ID: "work", Label: "工作", Hue: model.HueBlue, Order: 0, UpdatedAt: now},
			{ID: "study", Label: "学习", Hue: model.HueGreen, Order: 1, UpdatedAt: now},
			{ID: "life", Label: "生活", Hue: model.HueRed, Order: 2, UpdatedAt: now},
		}
	}

	// One-time migration for legacy v2 databases: persist normalized tasks (doing->flagged, default listId).
	var migratedTasks []model.Task
	if e.store.GetMeta("migrated_reminders_v1") != "1" {
		for _, t := range state.Tasks {
			t.Normalize()
			t.UpdatedAt = now
			if t.Stamps == nil {
				t.Stamps = map[string]int64{}
			}
			t.Stamps["status"] = now
			t.Stamps["flagged"] = now
			t.Stamps["listId"] = now
			migratedTasks = append(migratedTasks, t)
		}
		_ = e.store.SetMeta("migrated_reminders_v1", "1")
	}

	if len(migratedTasks) > 0 || len(seedTags) > 0 || len(seedLists) > 0 {
		_, _, _, _ = e.store.Upsert(migratedTasks, seedTags, seedLists)
	}
}

func newID(prefix string) string {
	var b [6]byte
	_, _ = rand.Read(b[:])
	return fmt.Sprintf("%s_%s", prefix, hex.EncodeToString(b[:]))
}
