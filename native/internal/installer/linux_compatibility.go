package installer

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"os"
	"strconv"
	"strings"
)

// Inspect the ASAR index read-only. Never execute or unpack vendor code.
func linuxHook(path string) error {
	f, e := os.Open(path)
	if e != nil {
		return errors.New("could not read Claude's extension compatibility information")
	}
	defer f.Close()
	header := make([]byte, 16)
	if _, e = io.ReadFull(f, header); e != nil {
		return errors.New("unsupported Claude archive")
	}
	headerSize := binary.LittleEndian.Uint32(header[4:])
	jsonSize := binary.LittleEndian.Uint32(header[12:])
	if headerSize < 8 || jsonSize > 8<<20 || jsonSize > headerSize-8 {
		return errors.New("unsupported Claude archive index")
	}
	b := make([]byte, jsonSize)
	if _, e = io.ReadFull(f, b); e != nil {
		return e
	}
	type entry struct {
		Files    map[string]json.RawMessage `json:"files"`
		Offset   string                     `json:"offset"`
		Size     int64                      `json:"size"`
		Unpacked bool                       `json:"unpacked"`
	}
	var index entry
	if json.Unmarshal(b, &index) != nil {
		return errors.New("unsupported Claude archive index")
	}
	found := map[string]bool{}
	total := int64(0)
	var walk func(map[string]json.RawMessage) error
	walk = func(files map[string]json.RawMessage) error {
		for name, raw := range files {
			var v entry
			if json.Unmarshal(raw, &v) != nil {
				return errors.New("invalid Claude archive entry")
			}
			if v.Files != nil {
				if e := walk(v.Files); e != nil {
					return e
				}
				continue
			}
			if !strings.HasSuffix(name, ".js") || v.Unpacked || v.Offset == "" {
				continue
			}
			offset, e := strconv.ParseInt(v.Offset, 10, 64)
			if e != nil || offset < 0 || v.Size < 0 || v.Size > 32<<20 {
				return errors.New("unsupported Claude archive entry size")
			}
			total += v.Size
			if total > 128<<20 {
				return errors.New("Claude compatibility scan exceeded its size limit")
			}
			data := make([]byte, v.Size)
			if _, e = f.ReadAt(data, int64(8)+int64(headerSize)+offset); e != nil {
				return e
			}
			for _, token := range []string{"REACT_PROFILE", "loadReactDevTools", ExtensionID, "loadExtension", "userData", "extensions"} {
				if bytes.Contains(data, []byte(token)) {
					found[token] = true
				}
			}
		}
		return nil
	}
	if e = walk(index.Files); e != nil {
		return e
	}
	if len(found) != 6 {
		return errors.New("this Claude version does not expose the required extension hook; no changes were made")
	}
	return nil
}
