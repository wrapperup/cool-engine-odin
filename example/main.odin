package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:sys/windows"
import "core:time"

import glfw "vendor:glfw"
import vk "vendor:vulkan"

import px "../deps/physx-odin"
import "../src/gfx"

main :: proc() {
	glfw.Init()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	window := glfw.CreateWindow(1920, 1080, "Triangle", nil, nil)

	if !gfx.init({window = window, enable_validation_layers = ODIN_DEBUG, enable_logs = ODIN_DEBUG}) {
		fmt.println("Graphics could not be initialized.")
	}

	Vertex :: struct {
		pos:   [3]f32,
		color: [3]f32,
	}

	vertices: [3]Vertex = {
		{{-0.5, -0.5, 0.0}, {1.0, 0.0, 0.0}}, 
		{{-0.5, 0.5, 0.0}, {0.0, 1.0, 0.0}}, 
		{{0.5, 0.5, 0.0}, {0.0, 0.0, 1.0}}
	}
	indices: [3]u32 = {0, 1, 2}

	vertex_buffer := gfx.create_buffer(size_of(vertices), {.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS}, .GPU_ONLY)
	index_buffer := gfx.create_buffer(size_of(indices), {.INDEX_BUFFER, .TRANSFER_DST}, .GPU_ONLY)

	gfx.staging_write_buffer_slice(&vertex_buffer, vertices[:])
	gfx.staging_write_buffer_slice(&index_buffer, indices[:])

	shader, ok := gfx.load_shader_module("assets/out/triangle.spv")
	assert(ok)

	triangle_pipeline_layout := gfx.create_pipeline_layout()

	triangle_pipeline := gfx.create_graphics_pipeline(
		{
			pipeline_layout = triangle_pipeline_layout,
			shader = shader,
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			front_face = .COUNTER_CLOCKWISE,
			color_format = gfx.renderer().draw_image.format,
		},
	)

	for !glfw.WindowShouldClose(window) {
		cmd := gfx.begin_command_buffer()

		gfx.transition_image(cmd, gfx.renderer().draw_image.image, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL)

		color_attachment := gfx.init_attachment_info(gfx.renderer().draw_image.image_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
		depth_attachment := gfx.init_attachment_info(
			gfx.renderer().depth_image.image_view,
			&{depthStencil = {depth = 1.0}},
			.DEPTH_ATTACHMENT_OPTIMAL,
		)
		render_info := gfx.init_rendering_info(gfx.renderer().draw_extent, &color_attachment, &depth_attachment)

		vk.CmdBeginRendering(cmd, &render_info)

		gfx.set_viewport_and_scissor(cmd, gfx.renderer().draw_extent)

		vk.CmdBindPipeline(cmd, .GRAPHICS, triangle_pipeline)

		offset := vk.DeviceSize(0)
		vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer.buffer, &offset)
		vk.CmdBindIndexBuffer(cmd, index_buffer.buffer, 0, .UINT32)

		vk.CmdDrawIndexed(cmd, len(indices), 1, 0, 0, 0)

		vk.CmdEndRendering(cmd)

		gfx.transition_image(cmd, gfx.renderer().draw_image.image, .UNDEFINED, .GENERAL)

		gfx.transition_image(cmd, gfx.renderer().draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
		gfx.copy_image_to_swapchain(cmd, gfx.renderer().draw_image.image, gfx.renderer().draw_extent)

		gfx.submit(cmd)

		// Free temp allocations
		free_all(context.temp_allocator)
	}
}

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
