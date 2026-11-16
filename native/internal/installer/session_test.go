package installer

import (
	"errors"
	"testing"
	"time"
)

type blockedOperations struct{ started, release, finished chan struct{} }

func (b *blockedOperations) Check() (Status, error) { return Status{}, nil }
func (b *blockedOperations) Install(Features) (Result, error) {
	close(b.started)
	<-b.release
	defer close(b.finished)
	return Result{}, errors.New("fixture operation completed with cleanup")
}
func (b *blockedOperations) InstallClaude(bool) error { return nil }
func TestSessionWaitsForCleanupAndRejectsLateWork(t *testing.T) {
	b := &blockedOperations{make(chan struct{}), make(chan struct{}), make(chan struct{})}
	s := NewSession(b)
	result := make(chan struct{})
	go func() { s.Install(Features{}); close(result) }()
	<-b.started
	closed := make(chan struct{})
	go func() { s.Close(); close(closed) }()
	select {
	case <-closed:
		t.Fatal("session returned before operation cleanup")
	case <-time.After(10 * time.Millisecond):
	}
	close(b.release)
	<-closed
	<-result
	select {
	case <-b.finished:
	default:
		t.Fatal("cleanup incomplete")
	}
	if _, e := s.Install(Features{}); e == nil {
		t.Fatal("late operation accepted")
	}
	if e := s.InstallClaude(true); e == nil {
		t.Fatal("late download accepted")
	}
}
