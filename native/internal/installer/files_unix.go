//go:build !windows

package installer

import (
	"os"
	"syscall"
)

const noFollowFlag = syscall.O_NOFOLLOW

func owned(s os.FileInfo, _ string) bool {
	st, ok := s.Sys().(*syscall.Stat_t)
	return ok && st.Uid == uint32(os.Getuid())
}
func ownedDir(s os.FileInfo, p string) bool {
	return s.IsDir() && s.Mode()&os.ModeSymlink == 0 && owned(s, p) && s.Mode().Perm()&0022 == 0
}
