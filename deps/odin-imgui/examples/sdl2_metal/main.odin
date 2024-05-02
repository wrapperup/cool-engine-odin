package imgui_example_sdl2_metal

// This is an example of using the bindings with SDL2 and Metal
// For a more complete example with comments, see:
// https://github.com/ocornut/imgui/blob/master/examples/example_sdl2_metal/main.mm
// (for updating: based on https://github.com/ocornut/imgui/blob/96839b445e32e46d87a44fd43a9cdd60c806f7e1/examples/example_sdl2_metal/main.mm)

// WARNING:
// This has been tested and is now working, but as an OjbC noob, the code is probably pretty bad.

#assert(ODIN_OS == .Darwin)

import im "../.."
import "../../imgui_impl_sdl2"
import "../../imgui_impl_metal"

import sdl "vendor:sdl2"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import NS "vendor:darwin/Foundation"

main :: proc() {
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
		style.Colors[im.Col.WindowBg].w = 1
	}
	im.StyleColorsDark()

	assert(sdl.Init(sdl.INIT_EVERYTHING) == 0)
	defer sdl.Quit()

	sdl.SetHint(sdl.HINT_RENDER_DRIVER, "metal")

	window := sdl.CreateWindow(
		"Dear ImGui SDL2+Metal example",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		1280, 720,
		{.RESIZABLE, .ALLOW_HIGHDPI})
	assert(window != nil)
	defer sdl.DestroyWindow(window)

	renderer := sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	defer sdl.DestroyRenderer(renderer)
	assert(renderer != nil)

	layer := cast(^CA.MetalLayer)sdl.RenderGetMetalLayer(renderer)
	layer->setPixelFormat(.BGRA8Unorm)

	imgui_impl_metal.Init(layer->device())
	defer imgui_impl_metal.Shutdown()
	imgui_impl_sdl2.InitForMetal(window)
	defer imgui_impl_sdl2.Shutdown()

	command_queue := layer->device()->newCommandQueue()
	render_pass_descriptor :^MTL.RenderPassDescriptor= MTL.RenderPassDescriptor.alloc()->init()

	running := true
	for running {
		e: sdl.Event
		for sdl.PollEvent(&e) {
			imgui_impl_sdl2.ProcessEvent(&e)

			#partial switch e.type {
			case .QUIT: running = false
			}
		}

		width, height: i32
		sdl.GetRendererOutputSize(renderer, &width, &height)
		layer->setDrawableSize(NS.Size{ NS.Float(width), NS.Float(height) })
		drawable := layer->nextDrawable()

		command_buffer := command_queue->commandBuffer()
		render_pass_descriptor->colorAttachments()->object(0)->setClearColor(MTL.ClearColor{ 0, 0, 0, 1 })
		render_pass_descriptor->colorAttachments()->object(0)->setTexture(drawable->texture())
		render_pass_descriptor->colorAttachments()->object(0)->setLoadAction(.Clear)
		render_pass_descriptor->colorAttachments()->object(0)->setStoreAction(.Store)

		render_encoder := command_buffer->renderCommandEncoderWithDescriptor(render_pass_descriptor)

		imgui_impl_metal.NewFrame(render_pass_descriptor)
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
		imgui_impl_metal.RenderDrawData(im.GetDrawData(), command_buffer, render_encoder)

		when im.IMGUI_BRANCH == "docking" {
			im.UpdatePlatformWindows()
			im.RenderPlatformWindowsDefault()
		}

		render_encoder->endEncoding()

		command_buffer->presentDrawable(drawable)
		command_buffer->commit()
	}
}
