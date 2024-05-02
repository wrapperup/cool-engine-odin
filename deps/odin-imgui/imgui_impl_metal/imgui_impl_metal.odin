// +build darwin
package imgui_impl_metal

import imgui "../"
import mtl "vendor:darwin/Metal"

// NOTE[TS]: This is a workaround to force link with QuartzCore, as required
// by the imgui metal implementation. Else you'd have to manually link.
// We also depend on libcxx, which we can hackily depend on by attaching it to this import.
@(require, extra_linker_flags="-lc++")
foreign import "system:QuartzCore.framework"

when      ODIN_OS == .Windows do foreign import lib "../imgui_windows_x64.lib"
else when ODIN_OS == .Linux   do foreign import lib "../imgui_linux_x64.a"
else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .amd64 { foreign import lib "../imgui_darwin_x64.a" } else { foreign import lib "../imgui_darwin_arm64.a" }
}

// imgui_impl_metal.h
// Last checked 357f752b
@(link_prefix="ImGui_ImplMetal_")
foreign lib {
	Init           :: proc(device: ^mtl.Device) -> bool ---
	Shutdown       :: proc() ---
	NewFrame       :: proc(renderPassDescriptor: ^mtl.RenderPassDescriptor) ---
	RenderDrawData :: proc(draw_data: ^imgui.DrawData,
						   commandBuffer: ^mtl.CommandBuffer,
						   commandEncoder: ^mtl.RenderCommandEncoder) ---

	// Called by Init/NewFrame/Shutdown
	CreateFontsTexture   :: proc(device: ^mtl.Device) -> bool ---
	DestroyFontsTexture  :: proc() ---
	CreateDeviceObjects  :: proc(device: ^mtl.Device) -> bool ---
	DestroyDeviceObjects :: proc() ---
}
