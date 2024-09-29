package main

import "core:math/linalg"
import "core:math/linalg/hlsl"

import vk "vendor:vulkan"

import vma "deps:odin-vma"

import gfx "gfx"

@(ShaderShared)
GPUDrawPushConstants :: struct {
	global_data_buffer_address: vk.DeviceAddress `GlobalData`,
	vertex_buffer_address:      vk.DeviceAddress `Vertex`,
	model_matrices_address:     vk.DeviceAddress `hlsl.float4x4`,
}

// 256 bytes is the maximum allowed in a push constant on a 3090Ti
// TODO: move matrices out into uniform
#assert(size_of(GPUDrawPushConstants) <= 256)

@(ShaderShared)
GPUGlobalData :: struct {
	view_projection_matrix:       hlsl.float4x4,
	view_projection_i_matrix:     hlsl.float4x4,
	sun_view_projection_matrix:   hlsl.float4x4,
	sun_view_projection_i_matrix: hlsl.float4x4,
	sun_color:                    hlsl.float3,
	bias:                         f32,
	sky_color:                    hlsl.float3,
	pad_0:                        f32,
	camera_pos:                   hlsl.float3,
	pad_1:                        f32,
	sun_pos:                      hlsl.float3,
	pad_2:                        f32,
}

//// INITIALIZATION
init_game_draw :: proc() {
	init_test_image()
	//init_shadow_map({1024, 1024, 1})
	init_shadow_map_old({1024, 1024, 1})
	init_descriptors()
	init_pipelines()
	init_buffers()
}

init_test_image :: proc() {
	game.TEMP_mesh_image = gfx.load_image_from_file(&game.renderer)
}

init_shadow_map :: proc(extent: vk.Extent3D) {
	game.shadow_depth_image = gfx.create_image(
		&game.renderer,
		.D32_SFLOAT,
		extent,
		{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
	)
	gfx.create_image_view(game.renderer.device, &game.shadow_depth_image, {.DEPTH})

	gfx.push_deletion_queue(&game.renderer.main_deletion_queue, game.shadow_depth_image.image_view)
	gfx.push_deletion_queue(
		&game.renderer.main_deletion_queue,
		game.shadow_depth_image.image,
		game.shadow_depth_image.allocation,
	)
}

init_shadow_map_old :: proc(extent: vk.Extent3D) {
	img_alloc_info := vma.AllocationCreateInfo {
		usage         = .GPU_ONLY,
		requiredFlags = {.DEVICE_LOCAL},
	}

	game.shadow_depth_image.format = .D32_SFLOAT
	game.shadow_depth_image.extent = extent
	depth_image_usages := vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED}

	dimg_info := gfx.init_image_create_info(game.shadow_depth_image.format, depth_image_usages, extent, ._1)

	//allocate and create the image
	vma.CreateImage(
		game.renderer.allocator,
		&dimg_info,
		&img_alloc_info,
		&game.shadow_depth_image.image,
		&game.shadow_depth_image.allocation,
		nil,
	)

	//build a image-view for the draw image to use for rendering
	dview_info := gfx.init_imageview_create_info(
	    game.shadow_depth_image.format,
		game.shadow_depth_image.image,
		{.DEPTH},
	)

	gfx.vk_check(vk.CreateImageView(game.renderer.device, &dview_info, nil, &game.shadow_depth_image.image_view))

	gfx.push_deletion_queue(&game.renderer.main_deletion_queue, game.shadow_depth_image.image_view)
	gfx.push_deletion_queue(
		&game.renderer.main_deletion_queue,
		game.shadow_depth_image.image,
		game.shadow_depth_image.allocation,
	)
}

init_descriptors :: proc() {
	game.mesh_descriptor_layout = gfx.create_descriptor_set_layout(
		game.renderer.device,
		{.VERTEX, .FRAGMENT},
		[?]gfx.DescriptorBinding{{0, .COMBINED_IMAGE_SAMPLER}, {1, .COMBINED_IMAGE_SAMPLER}},
	)

	game.mesh_descriptor_set = gfx.allocate_descriptor_set(
		&game.renderer.global_descriptor_allocator,
		game.renderer.device,
		game.mesh_descriptor_layout,
	)

	gfx.push_deletion_queue(&game.renderer.main_deletion_queue, game.mesh_descriptor_layout)

	// Shadow Depth Texture Sampler
	shadow_depth_sampler := gfx.create_sampler(game.renderer.device, .LINEAR, .CLAMP_TO_EDGE, .LESS_OR_EQUAL)
	gfx.push_deletion_queue(&game.renderer.main_deletion_queue, shadow_depth_sampler)

	// Test Texture Sampler
	TEMP_mesh_image_sampler := gfx.create_sampler(game.renderer.device, .LINEAR, .CLAMP_TO_EDGE)
	gfx.push_deletion_queue(&game.renderer.main_deletion_queue, TEMP_mesh_image_sampler)

	gfx.write_descriptor_set(
		game.renderer.device,
		game.mesh_descriptor_set,
		[]gfx.DescriptorWrite {
			gfx.DescriptorWriteImage {
				0,
				.COMBINED_IMAGE_SAMPLER,
				game.shadow_depth_image.image_view,
				shadow_depth_sampler,
				.DEPTH_READ_ONLY_OPTIMAL,
			},
			gfx.DescriptorWriteImage {
				1,
				.COMBINED_IMAGE_SAMPLER,
				game.TEMP_mesh_image.image_view,
				TEMP_mesh_image_sampler,
				.SHADER_READ_ONLY_OPTIMAL,
			},
		},
	)
}

init_pipelines :: proc() {
	init_mesh_pipelines()
}

init_mesh_pipelines :: proc() {
	triangle_shader, f_ok := gfx.load_shader_module("shaders/out/shaders.spv", game.renderer.device)
	assert(f_ok, "Failed to load shaders.")

	// TODO: This doesn't belong here...?
	{
		buffers, ok := gfx.load_mesh_from_file(&game.renderer, "assets/bunny.glb")
		assert(ok)

		game.mesh_buffers = buffers
	}
	{
		buffers, ok := gfx.load_mesh_from_file(&game.renderer, "assets/sphere.glb")
		assert(ok)

		game.sphere_mesh_buffers = buffers
	}

	buffer_range := vk.PushConstantRange {
		offset     = 0,
		size       = size_of(GPUDrawPushConstants),
		stageFlags = {.VERTEX, .FRAGMENT},
	}

	pipeline_layout_info := gfx.init_pipeline_layout_create_info()
	pipeline_layout_info.pPushConstantRanges = &buffer_range
	pipeline_layout_info.pushConstantRangeCount = 1
	pipeline_layout_info.pSetLayouts = &game.mesh_descriptor_layout
	pipeline_layout_info.setLayoutCount = 1

	gfx.vk_check(vk.CreatePipelineLayout(game.renderer.device, &pipeline_layout_info, nil, &game.mesh_pipeline_layout))

	pipeline_builder := gfx.pb_init()
	defer gfx.pb_delete(pipeline_builder)

	pipeline_builder.pipeline_layout = game.mesh_pipeline_layout
	gfx.pb_set_shaders(&pipeline_builder, triangle_shader)
	gfx.pb_set_input_topology(&pipeline_builder, .TRIANGLE_LIST)
	gfx.pb_set_polygon_mode(&pipeline_builder, .FILL)
	gfx.pb_set_cull_mode(&pipeline_builder, {.BACK}, .COUNTER_CLOCKWISE)
	gfx.pb_set_multisampling(&pipeline_builder, ._1)
	gfx.pb_disable_blending(&pipeline_builder)
	gfx.pb_enable_depthtest(&pipeline_builder, true, .LESS_OR_EQUAL)
	gfx.pb_set_color_attachment_format(&pipeline_builder, game.renderer.draw_image.format)
	gfx.pb_set_depth_format(&pipeline_builder, game.renderer.depth_image.format)

	game.mesh_pipeline = gfx.pb_build_pipeline(&pipeline_builder, game.renderer.device)

	gfx.pb_set_shaders(&pipeline_builder, triangle_shader, "vertex_shadow_main", "fragment_shadow_main")
	gfx.pb_disable_color_attachment(&pipeline_builder)
	game.mesh_shadow_pipeline = gfx.pb_build_pipeline(&pipeline_builder, game.renderer.device)

	vk.DestroyShaderModule(game.renderer.device, triangle_shader, nil)

	gfx.push_deletion_queue(&game.renderer.main_deletion_queue, game.mesh_pipeline_layout)
	gfx.push_deletion_queue(&game.renderer.main_deletion_queue, game.mesh_pipeline)
	gfx.push_deletion_queue(&game.renderer.main_deletion_queue, game.mesh_shadow_pipeline)

	gfx.push_deletion_queue(
		&game.renderer.main_deletion_queue,
		game.mesh_buffers.index_buffer.buffer,
		game.mesh_buffers.index_buffer.allocation,
	)
	gfx.push_deletion_queue(
		&game.renderer.main_deletion_queue,
		game.mesh_buffers.vertex_buffer.buffer,
		game.mesh_buffers.vertex_buffer.allocation,
	)
}

init_buffers :: proc() {
	for &frame in &game.renderer.frames {
		// Global uniform buffer
		frame.global_uniform_buffer = gfx.create_buffer(
			&game.renderer,
			size_of(GPUGlobalData),
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)

		frame.global_uniform_address = gfx.get_buffer_device_address(&game.renderer, frame.global_uniform_buffer)

		// Model matrices
		frame.model_matrices_buffer = gfx.create_buffer(
			&game.renderer,
			size_of(hlsl.float4x4) * 16_384,
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)

		frame.model_matrices_address = gfx.get_buffer_device_address(&game.renderer, frame.model_matrices_buffer)

		gfx.push_deletion_queue(
			&game.renderer.main_deletion_queue,
			frame.global_uniform_buffer.buffer,
			frame.global_uniform_buffer.allocation,
		)

		gfx.push_deletion_queue(
			&game.renderer.main_deletion_queue,
			frame.model_matrices_buffer.buffer,
			frame.model_matrices_buffer.allocation,
		)
	}

	// TODO: TEMP: GO AWAY?
	resize(&game.model_matrices, 16_384)
}

//// RENDERING
draw :: proc(cmd: vk.CommandBuffer) {
	// Begin shadow pass
	gfx.transition_image(cmd, game.shadow_depth_image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	draw_shadow_map(cmd)
	// End shadow pass

    // Clear
	gfx.transition_image(cmd, game.renderer.draw_image, .UNDEFINED, .GENERAL)
	draw_background(cmd)

	// Begin geometry pass
	gfx.transition_image(cmd, game.renderer.draw_image, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL)
	gfx.transition_image(cmd, game.renderer.depth_image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	gfx.transition_image(cmd, game.shadow_depth_image, .DEPTH_ATTACHMENT_OPTIMAL, .DEPTH_READ_ONLY_OPTIMAL)
	draw_geometry(cmd)
	// End geometry pass
}

draw_shadow_map :: proc(cmd: vk.CommandBuffer) {
	depth_attachment := gfx.init_depth_attachment_info(game.shadow_depth_image.image_view, .DEPTH_ATTACHMENT_OPTIMAL)

	width := game.shadow_depth_image.extent.width
	height := game.shadow_depth_image.extent.height

	render_info := gfx.init_rendering_info({width, height}, nil, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	gfx.set_viewport_and_scissor(cmd, game.shadow_depth_image.extent)

	vk.CmdBindPipeline(cmd, .GRAPHICS, game.mesh_shadow_pipeline)
	{
		vk.CmdBindDescriptorSets(cmd, .GRAPHICS, game.mesh_pipeline_layout, 0, 1, &game.mesh_descriptor_set, 0, nil)
		vk.CmdBindIndexBuffer(cmd, game.sphere_mesh_buffers.index_buffer.buffer, 0, .UINT32)

		push_constants: GPUDrawPushConstants
		push_constants.vertex_buffer_address = game.sphere_mesh_buffers.vertex_buffer_address
		push_constants.global_data_buffer_address = gfx.current_frame(&game.renderer).global_uniform_address
		push_constants.model_matrices_address = gfx.current_frame(&game.renderer).model_matrices_address

		vk.CmdPushConstants(
			cmd,
			game.mesh_pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			size_of(GPUDrawPushConstants),
			&push_constants,
		)

		vk.CmdDrawIndexed(cmd, game.sphere_mesh_buffers.index_count, u32(len_entities(Ball)), 0, 0, 0)
	}

	vk.CmdEndRendering(cmd)
}

draw_background :: proc(cmd: vk.CommandBuffer) {
	clear_color := vk.ClearColorValue {
		float32 = {0, 0.1, 0.1, 1},
	}

	clear_range := gfx.init_image_subresource_range({.COLOR})

	vk.CmdClearColorImage(cmd, game.renderer.draw_image.image, .GENERAL, &clear_color, 1, &clear_range)
}

draw_geometry :: proc(cmd: vk.CommandBuffer) {
	// begin a render pass  connected to our draw image
	color_attachment := gfx.init_attachment_info(game.renderer.draw_image.image_view, nil, .GENERAL)
	depth_attachment := gfx.init_depth_attachment_info(game.renderer.depth_image.image_view, .DEPTH_ATTACHMENT_OPTIMAL)

	// Start render pass.
	render_info := gfx.init_rendering_info(game.renderer.draw_extent, &color_attachment, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	gfx.set_viewport_and_scissor(cmd, game.renderer.draw_extent)

	vk.CmdBindPipeline(cmd, .GRAPHICS, game.mesh_pipeline)
	{
		vk.CmdBindDescriptorSets(cmd, .GRAPHICS, game.mesh_pipeline_layout, 0, 1, &game.mesh_descriptor_set, 0, nil)
		vk.CmdBindIndexBuffer(cmd, game.sphere_mesh_buffers.index_buffer.buffer, 0, .UINT32)

		push_constants: GPUDrawPushConstants
		push_constants.vertex_buffer_address = game.sphere_mesh_buffers.vertex_buffer_address
		push_constants.global_data_buffer_address = gfx.current_frame(&game.renderer).global_uniform_address
		push_constants.model_matrices_address = gfx.current_frame(&game.renderer).model_matrices_address

		vk.CmdPushConstants(
			cmd,
			game.mesh_pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			size_of(GPUDrawPushConstants),
			&push_constants,
		)

		vk.CmdDrawIndexed(cmd, game.sphere_mesh_buffers.index_count, u32(len_entities(Ball)), 0, 0, 0)
	}

	vk.CmdEndRendering(cmd)
}

update_buffers :: proc() {
	global_uniform_data: GPUGlobalData

	camera := get_entity(game.state.camera_id)

	// Camera matrices
	{
		aspect_ratio := f32(game.renderer.window_extent.width) / f32(game.renderer.window_extent.height)

		translation := linalg.matrix4_translate(camera != nil ? camera.translation : {})
		rotation := linalg.matrix4_from_quaternion(camera != nil ? camera.rotation : {})

		view_matrix := linalg.inverse(linalg.mul(translation, rotation))

		// view_matrix := linalg.matrix4_look_at_f32(game_state.camera_pos, {0, 0, 0}, {0, 1, 0})

		projection_matrix := gfx.matrix4_infinite_perspective_z0_f32(
			linalg.to_radians(camera != nil ? camera.camera_fov_deg : 0),
			aspect_ratio,
			0.1,
		)
		projection_matrix[1][1] *= -1.0

		global_uniform_data.view_projection_matrix = projection_matrix * view_matrix

		global_uniform_data.view_projection_i_matrix = linalg.matrix4_inverse(
			global_uniform_data.view_projection_matrix,
		)
	}

	// Global sun matrices
	{
		sun_view_matrix := linalg.matrix4_look_at_f32(
			game.state.environment.sun_pos,
			game.state.environment.sun_target,
			{0.0, 1.0, 0.0},
		)
		sun_projection_matrix := gfx.matrix_ortho3d_z0_f32(-50, 50, -50, 50, 0.1, 500.0)
		sun_projection_matrix[1][1] *= -1.0

		global_uniform_data.sun_view_projection_matrix = sun_projection_matrix * sun_view_matrix

		global_uniform_data.view_projection_i_matrix = linalg.matrix4_inverse(
			global_uniform_data.view_projection_matrix,
		)
	}

	global_uniform_data.sun_color = game.state.environment.sun_color
	global_uniform_data.sky_color = game.state.environment.sky_color
	global_uniform_data.bias = game.state.environment.bias

	global_uniform_data.camera_pos = hlsl.float3(camera != nil ? camera.translation : [3]f32{0, 0, 0})
	global_uniform_data.sun_pos = hlsl.float3(game.state.environment.sun_pos)

	gfx.write_buffer(&gfx.current_frame(&game.renderer).global_uniform_buffer, &global_uniform_data)

	parallel_for_entities(proc(entity: ^Ball, index: int, data: rawptr) {
			model_matrices := transmute(^[dynamic]hlsl.float4x4)data

			translation := linalg.matrix4_translate(entity.translation)
			rotation := linalg.matrix4_from_quaternion(entity.rotation)

			model_matrices[index] = linalg.mul(translation, rotation)
		}, &game.model_matrices)

	gfx.write_buffer_array(&gfx.current_frame(&game.renderer).model_matrices_buffer, game.model_matrices[:])
}
