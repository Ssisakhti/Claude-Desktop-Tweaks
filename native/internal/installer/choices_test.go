package installer

import (
	"bytes"
	"encoding/json"
	"testing"
)

func TestAppearanceChoiceReceiptRoundTrip(t *testing.T) {
	raw := []byte(`{"features":{"font":true,"theme":true,"rtl":false,"fontFamily":"vazirmatn","themeName":"gruvbox"}}`)
	r, e := decodeReceipt(raw)
	if e != nil {
		t.Fatal(e)
	}
	b, _ := json.Marshal(r.Features)
	if !bytes.Contains(b, []byte(`"vazirmatn"`)) || !bytes.Contains(b, []byte(`"gruvbox"`)) {
		t.Fatal("choices lost", string(b))
	}
	files, e := Payload(r.Features)
	if e != nil {
		t.Fatal(e)
	}
	if !bytes.Contains(files["content.js"], b) {
		t.Fatal("selected appearance missing")
	}
}
func TestInvalidAppearanceChoicesFailClosed(t *testing.T) {
	for _, extra := range []string{`"fontFamily":"unknown"`, `"themeName":"unknown"`, `"fontFamily":null`, `"extra":true`} {
		_, e := decodeReceipt([]byte(`{"features":{"font":true,"theme":true,"rtl":true,` + extra + `}}`))
		if e == nil {
			t.Fatal("invalid choice accepted", extra)
		}
	}
}
