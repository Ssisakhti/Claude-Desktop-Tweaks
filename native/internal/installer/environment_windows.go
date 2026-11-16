package installer

import (
	"errors"
	"runtime"
	"unsafe"

	"golang.org/x/sys/windows"
)

func notifyEnvironmentChange() error {
	message, e := windows.UTF16PtrFromString("Environment")
	if e != nil {
		return e
	}
	var result uintptr
	send := windows.NewLazySystemDLL("user32.dll").NewProc("SendMessageTimeoutW")
	status, _, _ := send.Call(0xffff, 0x001a, 0, uintptr(unsafe.Pointer(message)), 2, 2000, uintptr(unsafe.Pointer(&result)))
	runtime.KeepAlive(message)
	if status == 0 {
		return errors.New("Windows could not notify the desktop of the environment change")
	}
	return nil
}
