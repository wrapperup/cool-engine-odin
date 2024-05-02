package imgui_example_sdl2_directx11

// This is an example of using the bindings with SDL2 and DirectX 11
// For a more complete example with comments, see:
// https://github.com/ocornut/imgui/blob/docking/examples/example_sdl2_directx11/main.cpp
// (for updating: based on https://github.com/ocornut/imgui/blob/96839b445e32e46d87a44fd43a9cdd60c806f7e1/examples/example_sdl2_directx11/main.cpp)

import im "../.."
import "../../imgui_impl_sdl2"
import "../../imgui_impl_dx11"

import sdl "vendor:sdl2"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import "core:sys/windows"

g_pd3dDevice: ^d3d11.IDevice
g_pd3dDeviceContext: ^d3d11.IDeviceContext
g_pSwapChain: ^dxgi.ISwapChain
g_mainRenderTargetView: ^d3d11.IRenderTargetView

main :: proc() {
	assert(sdl.Init(sdl.INIT_EVERYTHING) == 0)
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Dear ImGui SDL2+OpenGl3 example",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		1280, 720,
		{.RESIZABLE, .ALLOW_HIGHDPI})
	assert(window != nil)
	defer sdl.DestroyWindow(window)

	wm_info: sdl.SysWMinfo
	sdl.GetWindowWMInfo(window, &wm_info)
	hwnd := cast(windows.HWND)wm_info.info.win.window

	if !create_device_d3d(hwnd) {
		cleanup_device_d3d()
		return
	}

	im.CHECKVERSION()
	im.CreateContext()
	defer im.DestroyContext()
	io := im.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}
	when im.IMGUI_BRANCH == "docking" {
		io.ConfigFlags += {.DockingEnable}
		io.ConfigFlags += {.ViewportsEnable}

		style := im.GetStyle()
		style.WindowRounding = 0
		style.Colors[im.Col.WindowBg].w =1
	}

	im.StyleColorsDark()

	imgui_impl_sdl2.InitForD3D(window)
	defer imgui_impl_sdl2.Shutdown() // here
	imgui_impl_dx11.Init(g_pd3dDevice, g_pd3dDeviceContext)
	defer imgui_impl_dx11.Shutdown()

	running := true
	for running {
		e: sdl.Event
		for sdl.PollEvent(&e) {
			imgui_impl_sdl2.ProcessEvent(&e)

			#partial switch e.type {
			case .QUIT: running = false
			}
		}

		imgui_impl_dx11.NewFrame()
		imgui_impl_sdl2.NewFrame()
		im.NewFrame()

		im.ShowDemoWindow()

		if im.Begin("Window containing a quit button") {
			if im.Button("The quit button in question") {
				running = false
			}
		}
		im.End()

		im.Render()
		g_pd3dDeviceContext->OMSetRenderTargets(1, &g_mainRenderTargetView, nil)
		g_pd3dDeviceContext->ClearRenderTargetView(g_mainRenderTargetView, &{ 0, 0, 0, 1 })
		imgui_impl_dx11.RenderDrawData(im.GetDrawData())

		when im.IMGUI_BRANCH == "docking" {
			if .ViewportsEnable in io.ConfigFlags {
				im.UpdatePlatformWindows()
				im.RenderPlatformWindowsDefault()
			}
		}

		g_pSwapChain->Present(1, {})
	}
}

create_device_d3d :: proc(hwnd: windows.HWND) -> bool {
	swapchain_desc := dxgi.SWAP_CHAIN_DESC {
		BufferCount = 2,
		BufferDesc = {
			Width = 0,
			Height = 0,
			Format =.R8G8B8A8_UNORM,
			RefreshRate = {
				Numerator = 60,
				Denominator = 1,
			},
		},
		Flags = {.ALLOW_MODE_SWITCH},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		OutputWindow = hwnd,
		SampleDesc = {
			Count = 1,
			Quality = 0,
		},
		Windowed =true,
		SwapEffect = .DISCARD,
	}

	create_device_flags: d3d11.CREATE_DEVICE_FLAGS
	feature_level: d3d11.FEATURE_LEVEL
	feature_levels: []d3d11.FEATURE_LEVEL = { ._11_0, ._10_0 }
	if d3d11.CreateDeviceAndSwapChain(
		nil,
		.HARDWARE,
		nil,
		create_device_flags,
		raw_data(feature_levels),
		u32(len(feature_levels)),
		d3d11.SDK_VERSION,
		&swapchain_desc,
		&g_pSwapChain,
		&g_pd3dDevice,
		&feature_level,
		&g_pd3dDeviceContext) != 0 {
			return false
	}

	create_render_target()

	return true
}

cleanup_device_d3d :: proc() {
	cleanup_render_target()
	if g_pSwapChain != nil { g_pSwapChain->Release(); g_pSwapChain = nil }
	if g_pd3dDeviceContext != nil { g_pd3dDeviceContext->Release(); g_pd3dDeviceContext = nil }
	if g_pd3dDevice != nil { g_pd3dDevice->Release(); g_pd3dDevice = nil }
}

create_render_target :: proc() {
	backbuffer: ^d3d11.ITexture2D
	g_pSwapChain->GetBuffer(0, d3d11.ITexture2D_UUID, cast(^rawptr)&backbuffer)
	g_pd3dDevice->CreateRenderTargetView(backbuffer, nil, &g_mainRenderTargetView)
	backbuffer->Release()
}

cleanup_render_target :: proc() {
	if g_mainRenderTargetView != nil { g_mainRenderTargetView->Release(); g_mainRenderTargetView = nil }
}
