package model

import (
	"encoding/json"
	"sort"
	"time"
)

// DefaultListID is the fallback list ID assigned to tasks without an explicit list.
const DefaultListID = "list_reminders"

// Status represents a task's completion state (Apple Reminders model: active vs completed).
// StatusDoing is retained only for backward-compatible migration to Flagged=true.
type Status string

const (
	StatusTodo  Status = "todo"
	StatusDoing Status = "doing"
	StatusDone  Status = "done"
)

// RepeatRule defines a recurrence cycle attached to a due date.
type RepeatRule string

const (
	RepeatNone    RepeatRule = ""
	RepeatDaily   RepeatRule = "daily"
	RepeatWeekly  RepeatRule = "weekly"
	RepeatMonthly RepeatRule = "monthly"
	RepeatYearly  RepeatRule = "yearly"
)

// TagHue is one of five refined semantic hues.
type TagHue string

const (
	HueBlue   TagHue = "blue"
	HueGreen  TagHue = "green"
	HuePurple TagHue = "purple"
	HueAmber  TagHue = "amber"
	HueRed    TagHue = "red"
)

// Subtask is a first-class structured checklist item owned by a Task.
type Subtask struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Done  bool   `json:"done"`
	Order int    `json:"order"`
}

// TaskList represents a user-defined Reminder list (e.g., 工作, 学习, 生活, 提醒).
type TaskList struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Color     string `json:"color"` // "blue"|"orange"|"green"|"red"|"purple"|"pink"|"yellow"|"gray"
	Icon      string `json:"icon"`  // "list"|"work"|"study"|"life"|"home"|"cart"|"star"|"book"|"code"|"heart"
	Order     int    `json:"order"`
	UpdatedAt int64  `json:"updatedAt"`
	Deleted   bool   `json:"deleted,omitempty"`
}

// Normalize ensures valid defaults on a TaskList.
func (l *TaskList) Normalize() {
	if l.Color == "" {
		l.Color = "blue"
	}
	if l.Icon == "" {
		l.Icon = "list"
	}
}

// Task is the core domain entity synchronized across macOS and Android.
type Task struct {
	ID          string           `json:"id"`
	Title       string           `json:"title"`
	Notes       string           `json:"notes"`
	Status      Status           `json:"status"`
	ListID      string           `json:"listId,omitempty"`
	Flagged     bool             `json:"flagged,omitempty"`
	Priority    int              `json:"priority,omitempty"` // 0=none, 1=low, 2=medium, 3=high
	URL         string           `json:"url,omitempty"`
	Subtasks    []Subtask        `json:"subtasks"`
	TagIDs      []string         `json:"tagIds"`
	DueAt       string           `json:"dueAt,omitempty"`       // Local "YYYY-MM-DDTHH:mm"
	RepeatRule  RepeatRule       `json:"repeatRule,omitempty"`
	Attachments []string         `json:"attachments,omitempty"` // Asset filenames (sha256.ext)
	Rank        float64          `json:"rank"`
	CompletedAt int64            `json:"completedAt,omitempty"` // Unix ms
	CreatedAt   int64            `json:"createdAt"`             // Unix ms
	UpdatedAt   int64            `json:"updatedAt"`             // Unix ms
	Deleted     bool             `json:"deleted,omitempty"`
	Stamps      map[string]int64 `json:"stamps,omitempty"`
}

// Tag is a user-defined label synchronized with tombstones.
type Tag struct {
	ID        string `json:"id"`
	Label     string `json:"label"`
	Hue       TagHue `json:"hue"`
	Order     int    `json:"order"`
	UpdatedAt int64  `json:"updatedAt"`
	Deleted   bool   `json:"deleted,omitempty"`
}

// BoardState is the full snapshot loaded by native clients.
type BoardState struct {
	Tasks  []Task     `json:"tasks"`
	Tags   []Tag      `json:"tags"`
	Lists  []TaskList `json:"lists"`
	Seeded bool       `json:"seeded"`
}

// DiscoveredPeer represents an online TODO device discovered via UDP broadcast on the LAN.
type DiscoveredPeer struct {
	DeviceID   string `json:"deviceId"`
	DeviceName string `json:"deviceName"`
	IP         string `json:"ip"`
	HTTPPort   int    `json:"httpPort"`
	LastSeenMs int64  `json:"lastSeenMs"`
}

// PairedPeer represents a persistently paired device stored in SQLite sync_peers.
type PairedPeer struct {
	DeviceID      string `json:"deviceId"`
	DeviceName    string `json:"deviceName"`
	PairingSecret string `json:"-"`
	LastSyncAt    int64  `json:"lastSyncAt"`
	LastIP        string `json:"lastIp"`
	LastPort      int    `json:"lastPort"`
	Online        bool   `json:"online"`
}

// SyncStatus summarizes overall LAN sync state (TradeFlow-style symmetric P2P).
type SyncStatus struct {
	Running           bool             `json:"running"`
	DeviceID          string           `json:"deviceId"`
	DeviceName        string           `json:"deviceName"`
	Address           string           `json:"address"`
	HTTPPort          int              `json:"httpPort"`
	ActivePairingCode string           `json:"activePairingCode,omitempty"`
	PairingExpiresAt  int64            `json:"pairingExpiresAt,omitempty"`
	PairedPeers       []PairedPeer     `json:"pairedPeers"`
	DiscoveredPeers   []DiscoveredPeer `json:"discoveredPeers"`
	SyncedAt          int64            `json:"syncedAt"`
	LastError         string           `json:"lastError,omitempty"`
}

// SyncEvent is pushed to native UI listeners via callback.
type SyncEvent struct {
	Type   string      `json:"type"` // "rows" | "status"
	Tasks  []Task      `json:"tasks,omitempty"`
	Tags   []Tag       `json:"tags,omitempty"`
	Lists  []TaskList  `json:"lists,omitempty"`
	Status *SyncStatus `json:"status,omitempty"`
	At     int64       `json:"at,omitempty"`
}

// Normalize ensures non-nil slices and valid defaults before serialization.
func (t *Task) Normalize() {
	if t.Status == StatusDoing {
		t.Status = StatusTodo
		t.Flagged = true
	}
	if t.Status == "" {
		t.Status = StatusTodo
	}
	if t.ListID == "" {
		t.ListID = DefaultListID
	}
	if t.Priority < 0 {
		t.Priority = 0
	} else if t.Priority > 3 {
		t.Priority = 3
	}
	if t.Subtasks == nil {
		t.Subtasks = []Subtask{}
	}
	if t.TagIDs == nil {
		t.TagIDs = []string{}
	}
	if t.Attachments == nil {
		t.Attachments = []string{}
	}
	if t.DueAt == "" {
		t.RepeatRule = RepeatNone
	}
	if t.Stamps == nil {
		t.Stamps = map[string]int64{}
	}
}

func fieldStamp(t Task, field string) int64 {
	if t.Stamps != nil {
		if s, ok := t.Stamps[field]; ok {
			return s
		}
	}
	return t.UpdatedAt
}

func tieWins(a, b any) bool {
	ja, _ := json.Marshal(a)
	jb, _ := json.Marshal(b)
	return string(ja) >= string(jb)
}

// MergeTask performs deterministic field-level LWW reconciliation between two copies of a task.
func MergeTask(a, b Task) Task {
	a.Normalize()
	b.Normalize()

	res := a
	if b.UpdatedAt > a.UpdatedAt {
		res = b
	}
	res.Stamps = make(map[string]int64, 16)
	newest := max(a.UpdatedAt, b.UpdatedAt)
	if a.CreatedAt > 0 && (b.CreatedAt == 0 || a.CreatedAt < b.CreatedAt) {
		res.CreatedAt = a.CreatedAt
	} else if b.CreatedAt > 0 {
		res.CreatedAt = b.CreatedAt
	}

	pick := func(field string, va, vb any, setA, setB func()) {
		sa := fieldStamp(a, field)
		sb := fieldStamp(b, field)
		var chosen int64
		if sa > sb || (sa == sb && tieWins(va, vb)) {
			setA()
			chosen = sa
		} else {
			setB()
			chosen = sb
		}
		res.Stamps[field] = chosen
		if chosen > newest {
			newest = chosen
		}
	}

	pick("title", a.Title, b.Title, func() { res.Title = a.Title }, func() { res.Title = b.Title })
	pick("notes", a.Notes, b.Notes, func() { res.Notes = a.Notes }, func() { res.Notes = b.Notes })
	pick("status", a.Status, b.Status, func() { res.Status = a.Status }, func() { res.Status = b.Status })
	pick("listId", a.ListID, b.ListID, func() { res.ListID = a.ListID }, func() { res.ListID = b.ListID })
	pick("flagged", a.Flagged, b.Flagged, func() { res.Flagged = a.Flagged }, func() { res.Flagged = b.Flagged })
	pick("priority", a.Priority, b.Priority, func() { res.Priority = a.Priority }, func() { res.Priority = b.Priority })
	pick("url", a.URL, b.URL, func() { res.URL = a.URL }, func() { res.URL = b.URL })
	pick("subtasks", a.Subtasks, b.Subtasks, func() { res.Subtasks = a.Subtasks }, func() { res.Subtasks = b.Subtasks })
	pick("tagIds", a.TagIDs, b.TagIDs, func() { res.TagIDs = a.TagIDs }, func() { res.TagIDs = b.TagIDs })
	pick("dueAt", a.DueAt, b.DueAt, func() { res.DueAt = a.DueAt }, func() { res.DueAt = b.DueAt })
	pick("repeatRule", a.RepeatRule, b.RepeatRule, func() { res.RepeatRule = a.RepeatRule }, func() { res.RepeatRule = b.RepeatRule })
	pick("attachments", a.Attachments, b.Attachments, func() { res.Attachments = a.Attachments }, func() { res.Attachments = b.Attachments })
	pick("rank", a.Rank, b.Rank, func() { res.Rank = a.Rank }, func() { res.Rank = b.Rank })
	pick("completedAt", a.CompletedAt, b.CompletedAt, func() { res.CompletedAt = a.CompletedAt }, func() { res.CompletedAt = b.CompletedAt })
	pick("deleted", a.Deleted, b.Deleted, func() { res.Deleted = a.Deleted }, func() { res.Deleted = b.Deleted })

	res.UpdatedAt = newest
	res.Normalize()
	return res
}

// MergeTag reconciles two copies of a tag by UpdatedAt (deterministic tie-break).
func MergeTag(a, b Tag) Tag {
	if b.UpdatedAt > a.UpdatedAt {
		return b
	}
	if a.UpdatedAt > b.UpdatedAt {
		return a
	}
	if tieWins(a, b) {
		return a
	}
	return b
}

// MergeList reconciles two copies of a TaskList by UpdatedAt (deterministic tie-break).
func MergeList(a, b TaskList) TaskList {
	a.Normalize()
	b.Normalize()
	if b.UpdatedAt > a.UpdatedAt {
		return b
	}
	if a.UpdatedAt > b.UpdatedAt {
		return a
	}
	if tieWins(a, b) {
		return a
	}
	return b
}

// AdvanceDue computes the next occurrence for a repeating task ("YYYY-MM-DDTHH:mm").
// Clamps shorter months (e.g., Jan 31 + 1 month -> Feb 28/29).
func AdvanceDue(dueAt string, rule RepeatRule) string {
	if dueAt == "" || rule == RepeatNone {
		return ""
	}
	layout := "2006-01-02T15:04"
	t, err := time.ParseInLocation(layout, dueAt, time.Local)
	if err != nil {
		return dueAt
	}
	switch rule {
	case RepeatDaily:
		return t.AddDate(0, 0, 1).Format(layout)
	case RepeatWeekly:
		return t.AddDate(0, 0, 7).Format(layout)
	case RepeatMonthly:
		return addMonthsClamped(t, 1).Format(layout)
	case RepeatYearly:
		return addMonthsClamped(t, 12).Format(layout)
	default:
		return dueAt
	}
}

func addMonthsClamped(t time.Time, months int) time.Time {
	year, month, day := t.Date()
	totalMonths := int(month) - 1 + months
	newYear := year + totalMonths/12
	newMonth := time.Month(totalMonths%12 + 1)
	lastDay := time.Date(newYear, newMonth+1, 0, 0, 0, 0, 0, t.Location()).Day()
	if day > lastDay {
		day = lastDay
	}
	return time.Date(newYear, newMonth, day, t.Hour(), t.Minute(), 0, 0, t.Location())
}

// SortTasks orders active tasks by Rank then CreatedAt ascending (so new items append above the phantom row).
// Completed tasks are sorted newest completedAt first.
func SortTasks(tasks []Task) {
	sort.SliceStable(tasks, func(i, j int) bool {
		a, b := tasks[i], tasks[j]
		aDone := a.Status == StatusDone
		bDone := b.Status == StatusDone
		if aDone != bDone {
			return !aDone
		}
		if aDone {
			return a.CompletedAt > b.CompletedAt
		}
		if a.Rank != b.Rank {
			return a.Rank < b.Rank
		}
		return a.CreatedAt < b.CreatedAt
	})
}
