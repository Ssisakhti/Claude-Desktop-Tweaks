package installer

import (
	"os"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// os.Root confines traversal; Lstat/reparse checks and SameFile guard each file.
const noFollowFlag = 0

func owned(s os.FileInfo, p string) bool {
	attributes, ok := s.Sys().(*syscall.Win32FileAttributeData)
	if !ok || attributes.FileAttributes&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
		return false
	}
	sd, e := windows.GetNamedSecurityInfo(p, windows.SE_FILE_OBJECT, windows.OWNER_SECURITY_INFORMATION|windows.DACL_SECURITY_INFORMATION)
	if e != nil {
		return false
	}
	user, e := windows.GetCurrentProcessToken().GetTokenUser()
	if e != nil {
		return false
	}
	trusted := func(sid *windows.SID) bool {
		return sid != nil && (sid.Equals(user.User.Sid) || sid.IsWellKnown(windows.WinLocalSystemSid) || sid.IsWellKnown(windows.WinBuiltinAdministratorsSid))
	}
	owner, _, e := sd.Owner()
	if e != nil || !trusted(owner) {
		return false
	}
	acl, _, e := sd.DACL()
	if e != nil || acl == nil {
		return false
	}
	const writeMask = windows.FILE_WRITE_DATA | windows.FILE_APPEND_DATA | windows.FILE_WRITE_EA | windows.FILE_WRITE_ATTRIBUTES | 0x40 /* FILE_DELETE_CHILD */ | windows.DELETE | windows.WRITE_DAC | windows.WRITE_OWNER | windows.GENERIC_WRITE | windows.GENERIC_ALL
	for n := uint32(0); n < uint32(acl.AceCount); n++ {
		var ace *windows.ACCESS_ALLOWED_ACE
		if windows.GetAce(acl, n, &ace) != nil {
			return false
		}
		if ace.Header.AceFlags&windows.INHERIT_ONLY != 0 {
			continue
		}
		if ace.Header.AceType == windows.ACCESS_DENIED_ACE_TYPE {
			continue
		}
		if ace.Header.AceType != windows.ACCESS_ALLOWED_ACE_TYPE {
			return false
		}
		if uint32(ace.Mask)&writeMask != 0 && !trusted((*windows.SID)(unsafe.Pointer(&ace.SidStart))) {
			return false
		}
	}
	return true
}
func ownedDir(s os.FileInfo, p string) bool {
	return s.IsDir() && s.Mode()&os.ModeSymlink == 0 && owned(s, p)
}
