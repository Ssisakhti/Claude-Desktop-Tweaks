package installer

import (
	"errors"
	"sync"
)

// Operations is the fixed set of local actions available to the interface.
type Operations interface {
	Check() (Status, error)
	Install(Features) (Result, error)
	InstallClaude(bool) error
}

// Session waits for started operations and rejects queued work after UI shutdown.
// This protects rollback even when terminal rendering fails or input closes.
type Session struct {
	service Operations
	mu      sync.Mutex
	active  sync.WaitGroup
	closed  bool
}

func NewSession(service Operations) *Session { return &Session{service: service} }
func (s *Session) begin() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return errors.New("setup session is closing; no new operation was started")
	}
	s.active.Add(1)
	return nil
}
func (s *Session) Check() (Status, error) {
	if e := s.begin(); e != nil {
		return Status{}, e
	}
	defer s.active.Done()
	return s.service.Check()
}
func (s *Session) Install(f Features) (Result, error) {
	if e := s.begin(); e != nil {
		return Result{}, e
	}
	defer s.active.Done()
	return s.service.Install(f)
}
func (s *Session) InstallClaude(yes bool) error {
	if e := s.begin(); e != nil {
		return e
	}
	defer s.active.Done()
	return s.service.InstallClaude(yes)
}
func (s *Session) Close() { s.mu.Lock(); s.closed = true; s.mu.Unlock(); s.active.Wait() }
