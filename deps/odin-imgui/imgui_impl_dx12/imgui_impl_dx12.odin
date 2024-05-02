// +build windows
package imgui_impl_dx12

import "core:c"

import imgui "../"
import "vendor:directx/d3d12"
import "vendor:directx/dxgi"

when      ODIN_OS == .Windows do foreign import lib "../imgui_windows_x64.lib"
else when ODIN_OS == .Linux   do foreign import lib "../imgui_linux_x64.a"
else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .amd64 { foreign import lib "../imgui_darwin_x64.a" } else { foreign import lib "../imgui_darwin_arm64.a" }
}

// imgui_impl_dx12.h
// Last checked 357f752b
@(link_prefix="ImGui_ImplDX12_")
foreign lib {
	// cmd_list is the command list that the implementation will use to render imgui draw lists.
	// Before calling the render function, caller must prepare cmd_list by resetting it and setting the appropriate
	// render target and descriptor heap that contains font_srv_cpu_desc_handle/font_srv_gpu_desc_handle.
	// font_srv_cpu_desc_handle and font_srv_gpu_desc_handle are handles to a single SRV descriptor to use for the internal font texture.
	Init :: proc(device: ^d3d12.IDevice, num_frames_in_flight: c.int, rtv_format: dxgi.FORMAT, cbv_srv_heap: ^d3d12.IDescriptorHeap,
		font_srv_cpu_desc_handle: d3d12.CPU_DESCRIPTOR_HANDLE, font_srv_gpu_desc_handle: d3d12.GPU_DESCRIPTOR_HANDLE) -> bool ---
	Shutdown       :: proc() ---
	NewFrame       :: proc() ---
	RenderDrawData :: proc(draw_data: ^imgui.DrawData, graphics_command_list: ^d3d12.IGraphicsCommandList) ---

	// Use if you want to reset your rendering device without losing Dear ImGui state.
	InvalidateDeviceObjects :: proc() ---
	CreateDeviceObjects     :: proc() -> bool ---
}
