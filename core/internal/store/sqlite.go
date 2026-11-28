package store

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	_ "modernc.org/sqlite"

	"navigator/core/internal/model"
)

const schema = `
CREATE TABLE IF NOT EXISTS tasks (
  id         TEXT PRIMARY KEY,
  body       TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  status     TEXT NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_tasks_updated ON tasks(updated_at);

CREATE TABLE IF NOT EXISTS tags (
  id         TEXT PRIMARY KEY,
  body       TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_tags_updated ON tags(updated_at);

CREATE TABLE IF NOT EXISTS lists (
  id         TEXT PRIMARY KEY,
  body       TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_lists_updated ON lists(updated_at);

CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
`

// Store manages the local SQLite database, separate image assets folder, and daily snapshots.
type Store struct {
	mu        sync.Mutex
	db        *sql.DB
	dataDir   string
	assetsDir string
	backupDir string
}

func Open(dataDir string) (*Store, error) {
	var dsn string
	var assetsDir, backupDir string
	if strings.TrimSpace(dataDir) == "" {
		dsn = ":memory:"
	} else {
		if err := os.MkdirAll(dataDir, 0o755); err != nil {
			return nil, fmt.Errorf("mkdir dataDir: %w", err)
		}
		assetsDir = filepath.Join(dataDir, "assets")
		backupDir = filepath.Join(dataDir, "backups")
		_ = os.MkdirAll(assetsDir, 0o755)
		_ = os.MkdirAll(backupDir, 0o755)
		dsn = filepath.Join(dataDir, "navigator.sqlite3")
	}

	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA busy_timeout=3000;`); err != nil {
		_ = db.Close()
		return nil, err
	}
	if _, err := db.Exec(schema); err != nil {
		_ = db.Close()
		return nil, err
	}
	return &Store{
		db:        db,
		dataDir:   dataDir,
		assetsDir: assetsDir,
		backupDir: backupDir,
	}, nil
}

func (s *Store) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.db != nil {
		return s.db.Close()
	}
	return nil
}

func (s *Store) LoadAll() (model.BoardState, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	tasks, err := s.queryTasks("SELECT body FROM tasks", nil)
	if err != nil {
		return model.BoardState{}, err
	}
	model.SortTasks(tasks)

	tags, err := s.queryTags("SELECT body FROM tags", nil)
	if err != nil {
		return model.BoardState{}, err
	}
	sort.SliceStable(tags, func(i, j int) bool {
		if tags[i].Order != tags[j].Order {
			return tags[i].Order < tags[j].Order
		}
		return tags[i].ID < tags[j].ID
	})

	lists, err := s.queryLists("SELECT body FROM lists", nil)
	if err != nil {
		return model.BoardState{}, err
	}
	sort.SliceStable(lists, func(i, j int) bool {
		if lists[i].Order != lists[j].Order {
			return lists[i].Order < lists[j].Order
		}
		return lists[i].ID < lists[j].ID
	})

	seeded := s.getMetaLocked("seeded") == "1"
	return model.BoardState{
		Tasks:  tasks,
		Tags:   tags,
		Lists:  lists,
		Seeded: seeded,
	}, nil
}

// GetTask fetches a single task by primary key without scanning the full table.
func (s *Store) GetTask(id string) (model.Task, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	var body string
	err := s.db.QueryRow("SELECT body FROM tasks WHERE id = ?", id).Scan(&body)
	if errors.Is(err, sql.ErrNoRows) {
		return model.Task{}, false, nil
	}
	if err != nil {
		return model.Task{}, false, err
	}
	var t model.Task
	if err := json.Unmarshal([]byte(body), &t); err != nil {
		return model.Task{}, false, err
	}
	t.Normalize()
	return t, true, nil
}

func (s *Store) ChangesSince(since int64) ([]model.Task, []model.Tag, []model.TaskList, int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	tasks, err := s.queryTasks("SELECT body FROM tasks WHERE updated_at >= ?", &since)
	if err != nil {
		return nil, nil, nil, 0, err
	}
	tags, err := s.queryTags("SELECT body FROM tags WHERE updated_at >= ?", &since)
	if err != nil {
		return nil, nil, nil, 0, err
	}
	lists, err := s.queryLists("SELECT body FROM lists WHERE updated_at >= ?", &since)
	if err != nil {
		return nil, nil, nil, 0, err
	}

	var at sql.NullInt64
	_ = s.db.QueryRow(`
		SELECT MAX(m) FROM (
			SELECT MAX(updated_at) AS m FROM tasks
			UNION ALL
			SELECT MAX(updated_at) AS m FROM tags
			UNION ALL
			SELECT MAX(updated_at) AS m FROM lists
		)
	`).Scan(&at)
	return tasks, tags, lists, at.Int64, nil
}

func (s *Store) Upsert(tasks []model.Task, tags []model.Tag, lists []model.TaskList) ([]model.Task, []model.Tag, []model.TaskList, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	tx, err := s.db.Begin()
	if err != nil {
		return nil, nil, nil, err
	}
	defer func() { _ = tx.Rollback() }()

	mergedTasks := make([]model.Task, 0, len(tasks))
	for _, incoming := range tasks {
		if incoming.ID == "" {
			continue
		}
		incoming.Normalize()
		var existingBody string
		err := tx.QueryRow("SELECT body FROM tasks WHERE id = ?", incoming.ID).Scan(&existingBody)
		final := incoming
		if err == nil {
			var existing model.Task
			if json.Unmarshal([]byte(existingBody), &existing) == nil {
				final = model.MergeTask(existing, incoming)
			}
		} else if !errors.Is(err, sql.ErrNoRows) {
			return nil, nil, nil, err
		}

		raw, err := json.Marshal(final)
		if err != nil {
			return nil, nil, nil, err
		}
		del := 0
		if final.Deleted {
			del = 1
		}
		_, err = tx.Exec(`
			INSERT INTO tasks (id, body, updated_at, status, deleted)
			VALUES (?, ?, ?, ?, ?)
			ON CONFLICT(id) DO UPDATE SET
				body = excluded.body,
				updated_at = excluded.updated_at,
				status = excluded.status,
				deleted = excluded.deleted
			WHERE excluded.updated_at >= tasks.updated_at
		`, final.ID, string(raw), final.UpdatedAt, string(final.Status), del)
		if err != nil {
			return nil, nil, nil, err
		}
		mergedTasks = append(mergedTasks, final)
	}

	mergedTags := make([]model.Tag, 0, len(tags))
	for _, incoming := range tags {
		if incoming.ID == "" {
			continue
		}
		var existingBody string
		err := tx.QueryRow("SELECT body FROM tags WHERE id = ?", incoming.ID).Scan(&existingBody)
		final := incoming
		if err == nil {
			var existing model.Tag
			if json.Unmarshal([]byte(existingBody), &existing) == nil {
				final = model.MergeTag(existing, incoming)
			}
		} else if !errors.Is(err, sql.ErrNoRows) {
			return nil, nil, nil, err
		}

		raw, err := json.Marshal(final)
		if err != nil {
			return nil, nil, nil, err
		}
		del := 0
		if final.Deleted {
			del = 1
		}
		_, err = tx.Exec(`
			INSERT INTO tags (id, body, updated_at, deleted)
			VALUES (?, ?, ?, ?)
			ON CONFLICT(id) DO UPDATE SET
				body = excluded.body,
				updated_at = excluded.updated_at,
				deleted = excluded.deleted
			WHERE excluded.updated_at >= tags.updated_at
		`, final.ID, string(raw), final.UpdatedAt, del)
		if err != nil {
			return nil, nil, nil, err
		}
		mergedTags = append(mergedTags, final)
	}

	mergedLists := make([]model.TaskList, 0, len(lists))
	for _, incoming := range lists {
		if incoming.ID == "" {
			continue
		}
		incoming.Normalize()
		var existingBody string
		err := tx.QueryRow("SELECT body FROM lists WHERE id = ?", incoming.ID).Scan(&existingBody)
		final := incoming
		if err == nil {
			var existing model.TaskList
			if json.Unmarshal([]byte(existingBody), &existing) == nil {
				final = model.MergeList(existing, incoming)
			}
		} else if !errors.Is(err, sql.ErrNoRows) {
			return nil, nil, nil, err
		}

		raw, err := json.Marshal(final)
		if err != nil {
			return nil, nil, nil, err
		}
		del := 0
		if final.Deleted {
			del = 1
		}
		_, err = tx.Exec(`
			INSERT INTO lists (id, body, updated_at, deleted)
			VALUES (?, ?, ?, ?)
			ON CONFLICT(id) DO UPDATE SET
				body = excluded.body,
				updated_at = excluded.updated_at,
				deleted = excluded.deleted
			WHERE excluded.updated_at >= lists.updated_at
		`, final.ID, string(raw), final.UpdatedAt, del)
		if err != nil {
			return nil, nil, nil, err
		}
		mergedLists = append(mergedLists, final)
	}

	_, _ = tx.Exec(`INSERT INTO meta (key, value) VALUES ('seeded', '1') ON CONFLICT(key) DO UPDATE SET value = '1'`)
	if err := tx.Commit(); err != nil {
		return nil, nil, nil, err
	}
	return mergedTasks, mergedTags, mergedLists, nil
}

func (s *Store) GetMeta(key string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.getMetaLocked(key)
}

func (s *Store) SetMeta(key, value string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, err := s.db.Exec(`INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value`, key, value)
	return err
}

func (s *Store) getMetaLocked(key string) string {
	var val string
	if err := s.db.QueryRow("SELECT value FROM meta WHERE key = ?", key).Scan(&val); err != nil {
		return ""
	}
	return val
}

func (s *Store) queryTasks(q string, since *int64) ([]model.Task, error) {
	var rows *sql.Rows
	var err error
	if since != nil {
		rows, err = s.db.Query(q, *since)
	} else {
		rows, err = s.db.Query(q)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]model.Task, 0)
	for rows.Next() {
		var body string
		if err := rows.Scan(&body); err != nil {
			return nil, err
		}
		var t model.Task
		if json.Unmarshal([]byte(body), &t) == nil {
			t.Normalize()
			out = append(out, t)
		}
	}
	return out, rows.Err()
}

func (s *Store) queryTags(q string, since *int64) ([]model.Tag, error) {
	var rows *sql.Rows
	var err error
	if since != nil {
		rows, err = s.db.Query(q, *since)
	} else {
		rows, err = s.db.Query(q)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]model.Tag, 0)
	for rows.Next() {
		var body string
		if err := rows.Scan(&body); err != nil {
			return nil, err
		}
		var t model.Tag
		if json.Unmarshal([]byte(body), &t) == nil {
			out = append(out, t)
		}
	}
	return out, rows.Err()
}

func (s *Store) queryLists(q string, since *int64) ([]model.TaskList, error) {
	var rows *sql.Rows
	var err error
	if since != nil {
		rows, err = s.db.Query(q, *since)
	} else {
		rows, err = s.db.Query(q)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]model.TaskList, 0)
	for rows.Next() {
		var body string
		if err := rows.Scan(&body); err != nil {
			return nil, err
		}
		var l model.TaskList
		if json.Unmarshal([]byte(body), &l) == nil {
			l.Normalize()
			out = append(out, l)
		}
	}
	return out, rows.Err()
}

// SaveAsset stores binary image data under assets/<sha256>.<ext> separated from SQLite rows.
func (s *Store) SaveAsset(data []byte, ext string) (string, error) {
	if s.assetsDir == "" {
		return "", errors.New("in-memory store has no assets directory")
	}
	ext = strings.TrimPrefix(strings.ToLower(strings.TrimSpace(ext)), ".")
	if ext == "" || len(ext) > 6 {
		ext = "webp"
	}
	sum := sha256.Sum256(data)
	name := fmt.Sprintf("%s.%s", hex.EncodeToString(sum[:16]), ext)
	dst := filepath.Join(s.assetsDir, name)
	if _, err := os.Stat(dst); err == nil {
		return name, nil
	}
	if err := os.WriteFile(dst, data, 0o644); err != nil {
		return "", err
	}
	return name, nil
}

func (s *Store) AssetPath(name string) string {
	if s.assetsDir == "" || strings.Contains(name, "/") || strings.Contains(name, "..") {
		return ""
	}
	return filepath.Join(s.assetsDir, name)
}

func (s *Store) ReadAsset(name string) ([]byte, error) {
	p := s.AssetPath(name)
	if p == "" {
		return nil, errors.New("invalid asset name")
	}
	return os.ReadFile(p)
}

func (s *Store) WriteAssetRaw(name string, data []byte) error {
	p := s.AssetPath(name)
	if p == "" {
		return errors.New("invalid asset name")
	}
	return os.WriteFile(p, data, 0o644)
}

func (s *Store) HasAsset(name string) bool {
	p := s.AssetPath(name)
	if p == "" {
		return false
	}
	_, err := os.Stat(p)
	return err == nil
}

// SnapshotDaily writes a daily JSON backup and retains the latest 7 days.
func (s *Store) SnapshotDaily() (string, error) {
	if s.backupDir == "" {
		return "", nil
	}
	day := time.Now().Format("2006-01-02")
	name := fmt.Sprintf("navigator-%s.json", day)
	dst := filepath.Join(s.backupDir, name)
	if _, err := os.Stat(dst); err == nil {
		return "exists", nil
	}
	state, err := s.LoadAll()
	if err != nil {
		return "", err
	}
	raw, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(dst, raw, 0o644); err != nil {
		return "", err
	}
	s.pruneBackupsLocked(7)
	return name, nil
}

func (s *Store) pruneBackupsLocked(keep int) {
	entries, err := os.ReadDir(s.backupDir)
	if err != nil {
		return
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasPrefix(e.Name(), "navigator-") && strings.HasSuffix(e.Name(), ".json") {
			names = append(names, e.Name())
		}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(names)))
	for i := keep; i < len(names); i++ {
		_ = os.Remove(filepath.Join(s.backupDir, names[i]))
	}
}

// PruneOrphanAssets removes unreferenced files in assets/ older than minAge
// (keeping a grace window so Undo and in-flight LAN sync stay safe).
func (s *Store) PruneOrphanAssets(minAge time.Duration) int {
	if s.assetsDir == "" {
		return 0
	}
	state, err := s.LoadAll()
	if err != nil {
		return 0
	}
	referenced := make(map[string]struct{})
	for _, t := range state.Tasks {
		if t.Deleted {
			continue
		}
		for _, name := range t.Attachments {
			if name != "" {
				referenced[name] = struct{}{}
			}
		}
	}
	entries, err := os.ReadDir(s.assetsDir)
	if err != nil {
		return 0
	}
	cutoff := time.Now().Add(-minAge)
	removed := 0
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		if _, ok := referenced[e.Name()]; ok {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		if info.ModTime().Before(cutoff) {
			if os.Remove(filepath.Join(s.assetsDir, e.Name())) == nil {
				removed++
			}
		}
	}
	return removed
}
