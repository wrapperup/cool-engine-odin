package imgui_example_null

// This is a copy of the "null" example from ImGui
// https://github.com/ocornut/imgui/blob/docking/examples/example_null/main.cpp
// (for updating: based on https://github.com/ocornut/imgui/blob/96839b445e32e46d87a44fd43a9cdd60c806f7e1/examples/example_null/main.cpp)

import im "../.."

import "core:fmt"

main :: proc() {
	im.CHECKVERSION()
	im.CreateContext()
	defer {
		fmt.println("DestroyContext()")
		im.DestroyContext()
	}
	io := im.GetIO()

	// Build atlas
	tex_pixels: ^u8
	tex_w, tex_h: i32
	im.FontAtlas_GetTexDataAsRGBA32(io.Fonts, &tex_pixels, &tex_w, &tex_h)

	for i in 0..<20 {
		fmt.printf("NewFrame() {}\n", i)
		io.DisplaySize = {1920, 1080}
		io.DeltaTime = 1.0 / 60.0
		im.NewFrame()

		@(static) f: f32
		im.Text("Hello, world!")
		im.SliderFloat("float", &f, 0, 1)
		im.Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0 / io.Framerate, io.Framerate)
		im.ShowDemoWindow()

		im.Render()
	}
}
