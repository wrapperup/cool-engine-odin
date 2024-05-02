package imgui_example_sdl2_sdlrenderer2

// This is an example of using the bindings with SDL2 and SDL_Renderer
// For a more complete example with comments, see:
// https://github.com/ocornut/imgui/blob/docking/examples/example_sdl2_sdlrenderer2/main.cpp
// (for updating: based on https://github.com/ocornut/imgui/blob/96839b445e32e46d87a44fd43a9cdd60c806f7e1/examples/example_sdl2_sdlrenderer2/main.cpp)

import im "../.."
import "../../imgui_impl_sdl2"
import "../../imgui_impl_sdlrenderer2"

import sdl "vendor:sdl2"
// Required for SDL_RenderGeometryRaw()
#assert(sdl.MAJOR_VERSION >= 2)
#assert(sdl.MINOR_VERSION >= 0)
#assert(sdl.PATCHLEVEL >= 18)

main :: proc() {
	assert(sdl.Init(sdl.INIT_EVERYTHING) == 0)
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Dear ImGui SDL2+SDL_Renderer example",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		1280, 720,
		{.RESIZABLE, .ALLOW_HIGHDPI})
	assert(window != nil)
	defer sdl.DestroyWindow(window)

	renderer := sdl.CreateRenderer(window, -1, {.PRESENTVSYNC, .ACCELERATED})
	assert(renderer != nil)
	defer sdl.DestroyRenderer(renderer)

	im.CHECKVERSION()
	im.CreateContext()
	defer im.DestroyContext()
	io := im.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}

	im.StyleColorsDark()

	imgui_impl_sdl2.InitForSDLRenderer(window, renderer)
	defer imgui_impl_sdl2.Shutdown()
	imgui_impl_sdlrenderer2.Init(renderer)
	defer imgui_impl_sdlrenderer2.Shutdown()

	running := true
	for running {
		e: sdl.Event
		for sdl.PollEvent(&e) {
			imgui_impl_sdl2.ProcessEvent(&e)

			#partial switch e.type {
			case .QUIT: running = false
			}
		}

		imgui_impl_sdlrenderer2.NewFrame()
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
		sdl.RenderSetScale(renderer, io.DisplayFramebufferScale.x, io.DisplayFramebufferScale.y)
		sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
		sdl.RenderClear(renderer)
		imgui_impl_sdlrenderer2.RenderDrawData(im.GetDrawData())
		sdl.RenderPresent(renderer)
	}
}
