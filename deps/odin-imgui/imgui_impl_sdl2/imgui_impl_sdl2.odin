package imgui_impl_sdl2

import sdl "vendor:sdl2"

when      ODIN_OS == .Windows do foreign import lib "../imgui_windows_x64.lib"
else when ODIN_OS == .Linux   do foreign import lib "../imgui_linux_x64.a"
else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .amd64 { foreign import lib "../imgui_darwin_x64.a" } else { foreign import lib "../imgui_darwin_arm64.a" }
}

// imgui_impl_sdl2.h
// Last checked 357f752b
@(link_prefix="ImGui_ImplSDL2_")
foreign lib {
	InitForOpenGL      :: proc(window: ^sdl.Window, sdl_gl_context: rawptr) -> bool ---
	InitForVulkan      :: proc(window: ^sdl.Window) -> bool ---
	InitForD3D         :: proc(window: ^sdl.Window) -> bool ---
	InitForMetal       :: proc(window: ^sdl.Window) -> bool ---
	InitForSDLRenderer :: proc(window: ^sdl.Window, renderer: ^sdl.Renderer) -> bool ---
	InitForOther       :: proc(window: ^sdl.Window) -> bool ---
	Shutdown           :: proc() ---
	NewFrame           :: proc() ---
	ProcessEvent       :: proc(event: ^sdl.Event) -> bool ---
}

// ImGui_ImplSDL2_NewFrame is elided as it is obsolete.
// Delete this when it's removed from dear imgui.
