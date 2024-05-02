package imgui_impl_glfw

import "core:c"

import "vendor:glfw"

when      ODIN_OS == .Windows do foreign import lib "../imgui_windows_x64.lib"
else when ODIN_OS == .Linux   do foreign import lib "../imgui_linux_x64.a"
else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .amd64 { foreign import lib "../imgui_darwin_x64.a" } else { foreign import lib "../imgui_darwin_arm64.a" }
}

// imgui_impl_glfw.h
// Last checked 3cb8054
@(link_prefix="ImGui_ImplGlfw_")
foreign lib {
	InitForOpenGL :: proc(window: glfw.WindowHandle, install_callbacks: bool) -> bool ---
	InitForVulkan :: proc(window: glfw.WindowHandle, install_callbacks: bool) -> bool ---
	InitForOther  :: proc(window: glfw.WindowHandle, install_callbacks: bool) -> bool ---
	Shutdown      :: proc() ---
	NewFrame      :: proc() ---

	// GLFW callbacks install
	// - When calling Init with 'install_callbacks=true': ImGui_ImplGlfw_InstallCallbacks() is called. GLFW callbacks will be installed for you. They will chain-call user's previously installed callbacks, if any.
	// - When calling Init with 'install_callbacks=false': GLFW callbacks won't be installed. You will need to call individual function yourself from your own GLFW callbacks.
	InstallCallbacks :: proc(window: glfw.WindowHandle) ---
	RestoreCallbacks :: proc(window: glfw.WindowHandle) ---

	// GFLW callbacks options:
	// - Set 'chain_for_all_windows=true' to enable chaining callbacks for all windows (including secondary viewports created by backends or by user)
	SetCallbacksChainForAllWindows :: proc(chain_for_all_windows: bool) ---

	// GLFW callbacks (individual callbacks to call yourself if you didn't install callbacks)
	WindowFocusCallback :: proc(window: glfw.WindowHandle, focused: c.int) --- // Since 1.84
	CursorEnterCallback :: proc(window: glfw.WindowHandle, entered: c.int) --- // Since 1.84
	CursorPosCallback   :: proc(window: glfw.WindowHandle, x: f64, y: f64) --- // Since 1.87
	MouseButtonCallback :: proc(window: glfw.WindowHandle, button: c.int, action: c.int, mods: c.int) ---
	ScrollCallback      :: proc(window: glfw.WindowHandle, xoffset: f64, yoffset: f64) ---
	KeyCallback         :: proc(window: glfw.WindowHandle, key: c.int, scancode: c.int, action: c.int, mods: c.int) ---
	CharCallback        :: proc(window: glfw.WindowHandle, c: c.uint) ---
	MonitorCallback     :: proc(monitor: glfw.MonitorHandle, event: c.int) ---
}
