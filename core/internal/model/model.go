package model

import (
	"encoding/json"
	"sort"
	"time"
)

// Status represents a task's lifecycle state.
// Completed tasks automatically live in the Logbook rather than occupying permanent board columns.
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

// Task is the core domain entity synchronized across macOS and Android.
type Task struct {
	ID          string           `json:"id"`
	Title       string           `json:"title"`
	Notes       string           `json:"notes"`
	Status      Status           `json:"status"`
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
	Tasks  []Task `json:"tasks"`
	Tags   []Tag  `json:"tags"`
	Seeded bool   `json:"seeded"`
}

// PeerStatus describes one LAN peer's sync health.
type PeerStatus struct {
	Addr  string `json:"addr"`
	OK    bool   `json:"ok"`
	At    int64  `json:"at"`
	Typed bool   `json:"typed"`
	Pair  string `json:"pair"` // "ok" | "wrong" | "locked"
	Retry int64  `json:"retry"`
}

// SyncStatus summarizes overall LAN sync state.
type SyncStatus struct {
	Listening   bool         `json:"listening"`
	Address     string       `json:"address"`
	PairCode    string       `json:"pairCode,omitempty"`
	Peers       []PeerStatus `json:"peers"`
	Unreachable bool         `json:"unreachable"`
	SyncedAt    int64        `json:"syncedAt"`
	Pair        string       `json:"pair"` // "need" | "ok" | "wrong" | "locked"
	Retry       int64        `json:"retry"`
}

// SyncEvent is pushed to native UI listeners via callback.
type SyncEvent struct {
	Type   string      `json:"type"` // "rows" | "status"
	Tasks  []Task      `json:"tasks,omitempty"`
	Tags   []Tag       `json:"tags,omitempty"`
	Status *SyncStatus `json:"status,omitempty"`
	At     int64       `json:"at,omitempty"`
}

// Normalize ensures non-nil slices and valid defaults before serialization.
func (t *Task) Normalize() {
	if t.Status == "" {
		t.Status = StatusTodo
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
	res.Stamps = make(map[string]int64, 12)
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

// SortTasks orders active tasks by due date first (nearest/overdue at top), then by rank.
// Completed tasks are sorted newest completedAt first.
func SortTasks(tasks []Task) {
	statusRank := func(s Status) int {
		switch s {
		case StatusDoing:
			return 0
		case StatusTodo:
			return 1
		case StatusDone:
			return 2
		default:
			return 3
		}
	}
	sort.SliceStable(tasks, func(i, j int) bool {
		a, b := tasks[i], tasks[j]
		sa, sb := statusRank(a.Status), statusRank(b.Status)
		if sa != sb {
			return sa < sb
		}
		if a.Status == StatusDone {
			return a.CompletedAt > b.CompletedAt
		}
		if a.DueAt != "" && b.DueAt != "" && a.DueAt != b.DueAt {
			return a.DueAt < b.DueAt
		}
		if (a.DueAt != "") != (b.DueAt != "") {
			return a.DueAt != ""
		}
		if a.Rank != b.Rank {
			return a.Rank < b.Rank
		}
		return a.CreatedAt > b.CreatedAt
	})
}
