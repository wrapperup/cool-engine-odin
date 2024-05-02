// +build windows
package imgui_impl_dx11

import imgui "../"
import "vendor:directx/d3d11"

when      ODIN_OS == .Windows do foreign import lib "../imgui_windows_x64.lib"
else when ODIN_OS == .Linux   do foreign import lib "../imgui_linux_x64.a"
else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .amd64 { foreign import lib "../imgui_darwin_x64.a" } else { foreign import lib "../imgui_darwin_arm64.a" }
}

// imgui_impl_dx11.h
// Last checked 357f752b
@(link_prefix="ImGui_ImplDX11_")
foreign lib {
	Init           :: proc(device: ^d3d11.IDevice, device_context: ^d3d11.IDeviceContext) -> bool ---
	Shutdown       :: proc() ---
	NewFrame       :: proc() ---
	RenderDrawData :: proc(draw_data: ^imgui.DrawData) ---

	// Use if you want to reset your rendering device without losing Dear ImGui state.
	InvalidateDeviceObjects :: proc() ---
	CreateDeviceObjects     :: proc() -> bool ---
}
