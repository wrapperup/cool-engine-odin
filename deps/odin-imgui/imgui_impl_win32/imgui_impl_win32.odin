// +build windows
package imgui_impl_win32

import "core:c"

import "core:sys/windows"

when      ODIN_OS == .Windows do foreign import lib "../imgui_windows_x64.lib"
else when ODIN_OS == .Linux   do foreign import lib "../imgui_linux_x64.a"
else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .amd64 { foreign import lib "../imgui_darwin_x64.a" } else { foreign import lib "../imgui_darwin_arm64.a" }
}

// imgui_impl_win32.h
// Last checked 357f752b

// Note a difference between the bindings an the actual impl:
// In the impl they didn't want to pull in <windows.h>, so they just used void*
// instead of HWND.
// ImGui_ImplWin32_WndProcHandler is additionally #if 0'd, for the same reason.
// This poses no issue for Odin, so we use HWND, and don't #if 0 out this function.
@(link_prefix="ImGui_ImplWin32_")
foreign lib {
	Init          :: proc(hwnd: windows.HWND) -> bool ---
	InitForOpenGL :: proc(hwnd: windows.HWND) -> bool ---
	Shutdown      :: proc() ---
	NewFrame      :: proc() ---

	// Win32 message handler your application need to call.
	// - Call from your application's message handler. Keep calling your message handler unless this function returns TRUE.
	WndProcHandler :: proc(hWnd: windows.HWND, msg: windows.UINT, wParam: windows.WPARAM, lParam: windows.LPARAM) -> windows.LRESULT ---

	// DPI-related helpers (optional)
	// - Use to enable DPI awareness without having to create an application manifest.
	// - Your own app may already do this via a manifest or explicit calls. This is mostly useful for our examples/ apps.
	// - In theory we could call simple functions from Windows SDK such as SetProcessDPIAware(), SetProcessDpiAwareness(), etc.
	//   but most of the functions provided by Microsoft require Windows 8.1/10+ SDK at compile time and Windows 8/10+ at runtime,
	//   neither we want to require the user to have. So we dynamically select and load those functions to avoid dependencies.
	EnableDpiAwareness    :: proc() ---
	GetDpiScaleForHwnd    :: proc(hwnd: windows.HWND) -> c.float ---
	GetDpiScaleForMonitor :: proc(monitor: windows.HMONITOR) -> c.float ---

	// Transparency related helpers (optional) [experimental]
	// - Use to enable alpha compositing transparency with the desktop.
	// - Use together with e.g. clearing your framebuffer with zero-alpha.
	EnableAlphaCompositing :: proc(hwnd: windows.HWND) ---
}
