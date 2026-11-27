package mobile

import (
	"navigator/core"
)

// EventListener is implemented by Kotlin on Android to receive real-time sync updates.
type EventListener interface {
	OnEvent(eventJSON string)
}

// NavigatorMobile wraps core.Engine with gomobile-compatible types.
type NavigatorMobile struct {
	engine *core.Engine
}

func Open(dataDir string) (*NavigatorMobile, error) {
	eng, err := core.Open(dataDir)
	if err != nil {
		return nil, err
	}
	return &NavigatorMobile{engine: eng}, nil
}

func (m *NavigatorMobile) SetListener(listener EventListener) {
	if listener == nil {
		m.engine.SetEventListener(nil)
		return
	}
	m.engine.SetEventListener(func(eventJSON string) {
		listener.OnEvent(eventJSON)
	})
}

func (m *NavigatorMobile) LoadJSON() (string, error) {
	return m.engine.LoadJSON()
}

func (m *NavigatorMobile) SaveTaskJSON(taskJSON string) (string, error) {
	return m.engine.SaveTaskJSON(taskJSON)
}

func (m *NavigatorMobile) CompleteTask(taskID string, done bool) (string, error) {
	return m.engine.CompleteTask(taskID, done)
}

func (m *NavigatorMobile) DeleteTask(taskID string, deleted bool) error {
	return m.engine.DeleteTask(taskID, deleted)
}

func (m *NavigatorMobile) SaveTagJSON(tagJSON string) (string, error) {
	return m.engine.SaveTagJSON(tagJSON)
}

func (m *NavigatorMobile) DeleteTag(tagID string) error {
	return m.engine.DeleteTag(tagID)
}

func (m *NavigatorMobile) SaveAsset(data []byte, ext string) (string, error) {
	return m.engine.SaveAsset(data, ext)
}

func (m *NavigatorMobile) AssetPath(name string) string {
	return m.engine.AssetPath(name)
}

func (m *NavigatorMobile) StartSync(serve bool, port int) (string, error) {
	return m.engine.StartSync(serve, port)
}

func (m *NavigatorMobile) SetPeerCode(code string) error {
	return m.engine.SetPeerCode(code)
}

func (m *NavigatorMobile) AddPeerAddress(addr string) {
	m.engine.AddPeerAddress(addr)
}

func (m *NavigatorMobile) SyncNow() {
	m.engine.SyncNow()
}

func (m *NavigatorMobile) SyncStatusJSON() string {
	return m.engine.SyncStatusJSON()
}

func (m *NavigatorMobile) ExportMarkdown() (string, error) {
	return m.engine.ExportMarkdown()
}

func (m *NavigatorMobile) ImportJSON(raw string) error {
	return m.engine.ImportJSON(raw)
}

func (m *NavigatorMobile) Close() error {
	return m.engine.Close()
}
