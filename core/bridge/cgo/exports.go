package main

/*
#include <stdlib.h>

typedef void (*nav_event_cb)(const char *event_json);

static inline void invoke_nav_cb(nav_event_cb cb, const char *msg) {
    if (cb != NULL) {
        cb(msg);
    }
}
*/
import "C"

import (
	"sync"
	"unsafe"

	"navigator/core"
)

var (
	engMu  sync.Mutex
	engine *core.Engine
	cbMu   sync.Mutex
	cbFunc C.nav_event_cb
)

func strOut(s string) *C.char {
	return C.CString(s)
}

func errJSON(err error) *C.char {
	if err == nil {
		return C.CString(`{"ok":true}`)
	}
	return C.CString(`{"error":` + quote(err.Error()) + `}`)
}

func quote(s string) string {
	b := make([]byte, 0, len(s)+2)
	b = append(b, '"')
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '"':
			b = append(b, '\\', '"')
		case '\\':
			b = append(b, '\\', '\\')
		case '\n':
			b = append(b, '\\', 'n')
		default:
			b = append(b, s[i])
		}
	}
	b = append(b, '"')
	return string(b)
}

//export NavFreeString
func NavFreeString(p *C.char) {
	if p != nil {
		C.free(unsafe.Pointer(p))
	}
}

//export NavOpen
func NavOpen(dataDir *C.char) *C.char {
	engMu.Lock()
	defer engMu.Unlock()
	if engine != nil {
		return strOut(`{"ok":true}`)
	}
	eng, err := core.Open(C.GoString(dataDir))
	if err != nil {
		return errJSON(err)
	}
	eng.SetEventListener(func(eventJSON string) {
		cbMu.Lock()
		fn := cbFunc
		cbMu.Unlock()
		if fn != nil {
			cs := C.CString(eventJSON)
			C.invoke_nav_cb(fn, cs)
			C.free(unsafe.Pointer(cs))
		}
	})
	engine = eng
	return strOut(`{"ok":true}`)
}

//export NavSetEventCallback
func NavSetEventCallback(cb C.nav_event_cb) {
	cbMu.Lock()
	cbFunc = cb
	cbMu.Unlock()
}

//export NavLoadJSON
func NavLoadJSON() *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"tasks":[],"tags":[],"lists":[],"seeded":false}`)
	}
	s, err := eng.LoadJSON()
	if err != nil {
		return errJSON(err)
	}
	return strOut(s)
}

//export NavSaveTaskJSON
func NavSaveTaskJSON(taskJSON *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	s, err := eng.SaveTaskJSON(C.GoString(taskJSON))
	if err != nil {
		return errJSON(err)
	}
	return strOut(s)
}

//export NavCompleteTask
func NavCompleteTask(taskID *C.char, done C.int) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	s, err := eng.CompleteTask(C.GoString(taskID), done != 0)
	if err != nil {
		return errJSON(err)
	}
	return strOut(s)
}

//export NavDeleteTask
func NavDeleteTask(taskID *C.char, deleted C.int) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	return errJSON(eng.DeleteTask(C.GoString(taskID), deleted != 0))
}

//export NavSaveTagJSON
func NavSaveTagJSON(tagJSON *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	s, err := eng.SaveTagJSON(C.GoString(tagJSON))
	if err != nil {
		return errJSON(err)
	}
	return strOut(s)
}

//export NavDeleteTag
func NavDeleteTag(tagID *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	return errJSON(eng.DeleteTag(C.GoString(tagID)))
}

//export NavSaveListJSON
func NavSaveListJSON(listJSON *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	s, err := eng.SaveListJSON(C.GoString(listJSON))
	if err != nil {
		return errJSON(err)
	}
	return strOut(s)
}

//export NavDeleteList
func NavDeleteList(listID *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	return errJSON(eng.DeleteList(C.GoString(listID)))
}

//export NavClearCompleted
func NavClearCompleted(listID *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	s, err := eng.ClearCompleted(C.GoString(listID))
	if err != nil {
		return errJSON(err)
	}
	return strOut(s)
}

//export NavSaveAsset
func NavSaveAsset(data unsafe.Pointer, length C.int, ext *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut("")
	}
	bytes := C.GoBytes(data, length)
	name, err := eng.SaveAsset(bytes, C.GoString(ext))
	if err != nil {
		return strOut("")
	}
	return strOut(name)
}

//export NavAssetPath
func NavAssetPath(name *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut("")
	}
	return strOut(eng.AssetPath(C.GoString(name)))
}

//export NavStartSync
func NavStartSync(serve C.int, port C.int) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	s, err := eng.StartSync(serve != 0, int(port))
	if err != nil {
		return errJSON(err)
	}
	return strOut(s)
}

//export NavGeneratePairingCode
func NavGeneratePairingCode() *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut("")
	}
	code, err := eng.GeneratePairingCode()
	if err != nil {
		return strOut("")
	}
	return strOut(code)
}

//export NavPairWithPeer
func NavPairWithPeer(ip *C.char, port C.int, code *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	s, err := eng.PairWithPeer(C.GoString(ip), int(port), C.GoString(code))
	if err != nil {
		return errJSON(err)
	}
	return strOut(s)
}

//export NavDeletePairedPeer
func NavDeletePairedPeer(deviceID *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	return errJSON(eng.DeletePairedPeer(C.GoString(deviceID)))
}

//export NavSyncWithPeer
func NavSyncWithPeer(deviceID *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	return errJSON(eng.SyncWithPeer(C.GoString(deviceID)))
}

//export NavSyncNow
func NavSyncNow() {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng != nil {
		eng.SyncNow()
	}
}

//export NavSyncStatusJSON
func NavSyncStatusJSON() *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{}`)
	}
	return strOut(eng.SyncStatusJSON())
}

//export NavExportMarkdown
func NavExportMarkdown() *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut("")
	}
	s, err := eng.ExportMarkdown()
	if err != nil {
		return strOut("")
	}
	return strOut(s)
}

//export NavImportJSON
func NavImportJSON(raw *C.char) *C.char {
	engMu.Lock()
	eng := engine
	engMu.Unlock()
	if eng == nil {
		return strOut(`{"error":"engine not open"}`)
	}
	return errJSON(eng.ImportJSON(C.GoString(raw)))
}

func main() {}
