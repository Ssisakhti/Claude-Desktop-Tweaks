package ui

import (
	"os"
	"testing"
)

// Optional visual artifact from the real renderer, using synthetic settings only.
func TestRendererPreview(t *testing.T) {
	m, _ := ready()
	m.screen = "theme"
	m.width = 110
	m.height = 36
	if file := os.Getenv("CDT_UI_SNAPSHOT"); file != "" {
		if err := os.WriteFile(file, []byte(m.View().Content), 0600); err != nil {
			t.Fatal(err)
		}
	}
}
