package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"

import vk "vendor:vulkan"

import vma "deps:odin-vma"

import gfx "gfx"

MAX_BINDLESS_IMAGES :: 100
MAX_BINDLESS_SAMPLERS :: 32

@(ShaderShared)
GPUDrawPushConstants :: struct {
	global_data_buffer: gfx.GPUPointer(GPUGlobalData),
	vertex_buffer:      gfx.GPUPointer(gfx.Vertex),
	model_matrices:     gfx.GPUPointer(hlsl.float4x4),
}

@(ShaderShared)
GPUSkelDrawPushConstants :: struct {
	global_data_buffer: gfx.GPUPointer(GPUGlobalData),
	vertex_buffer:      gfx.GPUPointer(gfx.Vertex),
	model_matrices:     gfx.GPUPointer(hlsl.float4x4),
	joint_matrices:     gfx.GPUPointer(hlsl.float4x4),
	attrs:              gfx.GPUPointer(gfx.SkeletonVertexAttribute),
}

// 256 bytes is the maximum allowed in a push constant on a 3090Ti
// TODO: move matrices out into uniform
#assert(size_of(GPUDrawPushConstants) <= 256)
#assert(size_of(GPUSkelDrawPushConstants) <= 256)

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

GameFrameData :: struct {
	global_uniform_buffer:       gfx.AllocatedBuffer,
	global_uniform_address:      gfx.GPUPointer(GPUGlobalData),
	model_matrices_buffer:       gfx.AllocatedBuffer,
	model_matrices_address:      gfx.GPUPointer(hlsl.float4x4),
	test_joint_matrices_buffer:  gfx.AllocatedBuffer,
	test_joint_matrices_address: gfx.GPUPointer(hlsl.float4x4),
}

current_frame_game :: proc() -> ^GameFrameData {
	return &game.frame_data[gfx.current_frame_index()]
}

//// INITIALIZATION
init_game_draw :: proc() {
	init_test_image()
	init_shadow_map({1024, 1024, 1})
	init_descriptors()
	init_pipelines()
	init_buffers()
}

init_test_image :: proc() {
}

init_shadow_map :: proc(extent: vk.Extent3D) {
	game.shadow_depth_image = gfx.create_image(.D32_SFLOAT, extent, {.DEPTH_STENCIL_ATTACHMENT, .SAMPLED})
	gfx.create_image_view(&game.shadow_depth_image, {.DEPTH})

	// TODO: r_ctx
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, game.shadow_depth_image.image_view)
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, game.shadow_depth_image.image, game.shadow_depth_image.allocation)
}

init_descriptors :: proc() {
	init_bindless_descriptors()
}

init_bindless_descriptors :: proc() {
	game.bindless_descriptor_layout = gfx.create_descriptor_set_layout(
		[?]gfx.DescriptorBinding {
			{binding = 0, type = .SAMPLED_IMAGE, count = MAX_BINDLESS_IMAGES},
			{binding = 1, type = .SAMPLER, count = MAX_BINDLESS_SAMPLERS},
			{binding = 2, type = .STORAGE_IMAGE},
		},
		{.UPDATE_AFTER_BIND_POOL},
		{.VERTEX, .FRAGMENT, .COMPUTE},
	)
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, game.bindless_descriptor_layout)

	game.bindless_descriptor_set = gfx.allocate_descriptor_set(
		&gfx.renderer().global_descriptor_allocator,
		gfx.renderer().device,
		game.bindless_descriptor_layout,
	)

	a := gfx.load_image_from_file("assets/test1.ktx")
	b := gfx.load_image_from_file("assets/test2.ktx")
	c := gfx.load_image_from_file("assets/test3.ktx")
	d := gfx.load_image_from_file("assets/test4.ktx")
	e := gfx.load_image_from_file("assets/test5.ktx")
	tony_mc_mapface := gfx.load_image_from_file("assets/tony-mc-mapface.ktx2")

	// Default Texture Sampler
	TEMP_mesh_image_sampler := gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE)
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, TEMP_mesh_image_sampler)

	// Shadow Depth Texture Sampler
	shadow_depth_sampler := gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE, .LESS_OR_EQUAL)
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, shadow_depth_sampler)

	gfx.write_descriptor_set(
		game.bindless_descriptor_set,
		[]gfx.DescriptorWrite {
			gfx.DescriptorWriteImage {
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = game.shadow_depth_image.image_view,
				image_layout = .DEPTH_READ_ONLY_OPTIMAL,
				array_index = 0,
			},
			gfx.DescriptorWriteImage {
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = a.image_view,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = 1,
			},
			gfx.DescriptorWriteImage {
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = b.image_view,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = 2,
			},
			gfx.DescriptorWriteImage {
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = c.image_view,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = 3,
			},
			gfx.DescriptorWriteImage {
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = d.image_view,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = 4,
			},
			gfx.DescriptorWriteImage {
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = e.image_view,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = 5,
			},
			gfx.DescriptorWriteImage {
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = tony_mc_mapface.image_view,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = 6,
			},
			gfx.DescriptorWriteImage {
				binding = 1,
				type = .SAMPLER,
				sampler = TEMP_mesh_image_sampler,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = 0,
			},
			gfx.DescriptorWriteImage {
				binding = 1,
				type = .SAMPLER,
				sampler = shadow_depth_sampler,
				image_layout = .DEPTH_READ_ONLY_OPTIMAL,
				array_index = 1,
			},
			gfx.DescriptorWriteImage {
				binding = 2,
				type = .STORAGE_IMAGE,
				image_view = gfx.renderer().draw_image.image_view,
				image_layout = .GENERAL,
			},
		},
	)
}

init_pipelines :: proc() {
	init_mesh_pipelines()
	init_tonemapper_pipelines()
}

init_mesh_pipelines :: proc() {
	triangle_shader, f_ok := gfx.load_shader_module("shaders/out/shaders.spv")
	assert(f_ok, "Failed to load shaders.")

	// game.mesh_pipeline_layout = gfx.create_pipeline_layout(gfx.renderer().device, &game.bindless_descriptor_layout, GPUDrawPushConstants)
	game.skel_mesh_pipeline_layout = gfx.create_pipeline_layout_pc(
		gfx.renderer().device,
		&game.bindless_descriptor_layout,
		GPUSkelDrawPushConstants,
	)

	// game.mesh_pipeline = gfx.create_graphics_pipeline(
	// 	{
	// 		pipeline_layout = game.mesh_pipeline_layout,
	// 		shader = triangle_shader,
	// 		input_topology = .TRIANGLE_LIST,
	// 		polygon_mode = .FILL,
	// 		cull_mode = {.BACK},
	// 		front_face = .COUNTER_CLOCKWISE,
	// 		depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
	// 		color_format = gfx.renderer().draw_image.format,
	// 	},
	// )
	//
	// game.mesh_shadow_pipeline = gfx.create_graphics_pipeline(
	// 	{
	// 		pipeline_layout = game.mesh_pipeline_layout,
	// 		shader = triangle_shader,
	// 		vertex_entry = "vertex_shadow_main",
	// 		fragment_entry = "fragment_shadow_main",
	// 		input_topology = .TRIANGLE_LIST,
	// 		polygon_mode = .FILL,
	// 		cull_mode = {.BACK},
	// 		front_face = .COUNTER_CLOCKWISE,
	// 		depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
	// 	},
	// )

	game.skel_mesh_pipeline = gfx.create_graphics_pipeline(
		{
			pipeline_layout = game.skel_mesh_pipeline_layout,
			shader = triangle_shader,
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = {.BACK},
			front_face = .COUNTER_CLOCKWISE,
			depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
			color_format = gfx.renderer().draw_image.format,
			multisampling_samples = gfx.msaa_samples(),
		},
	)

	gfx.destroy_shader_module(triangle_shader)

	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, game.mesh_pipeline_layout)
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, game.skel_mesh_pipeline_layout)

	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, game.mesh_pipeline)
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, game.mesh_shadow_pipeline)
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, game.skel_mesh_pipeline)
}

init_tonemapper_pipelines :: proc() {
	tonemapper_shader, f_ok := gfx.load_shader_module("shaders/out/tonemapping.spv")
	assert(f_ok, "Failed to load shaders.")

	game.tonemapper_pipeline_layout = gfx.create_pipeline_layout(gfx.renderer().device, &game.bindless_descriptor_layout)

	game.tonemapper_pipeline = gfx.create_compute_pipelines(game.tonemapper_pipeline_layout, tonemapper_shader)

	gfx.destroy_shader_module(tonemapper_shader)

	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, game.tonemapper_pipeline)
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, game.tonemapper_pipeline_layout)
}

init_buffers :: proc() {
	// Test meshes for game
	{
		{
			buffers, skeleton, anim, ok := gfx.load_skel_mesh_from_file("assets/materialball.glb")
			assert(ok)
			game.skel_mesh_buffers = buffers
			game.skel = skeleton
			game.skel_anim = anim

			gfx.init_skeleton_animator(&game.skel_animator, &game.skel, &game.skel_anim)

			fmt.println(game.skel)
		}

		buffers, ok := gfx.load_mesh_from_file("assets/skeltest.glb")
		assert(ok)
		game.sphere_mesh_buffers = buffers

		gfx.push_deletion_queue(
			&gfx.renderer().main_deletion_queue,
			game.sphere_mesh_buffers.vertex_buffer.buffer,
			game.sphere_mesh_buffers.vertex_buffer.allocation,
		)
	}

	for &frame in &game.frame_data {
		// Global uniform buffer
		frame.global_uniform_buffer = gfx.create_buffer(size_of(GPUGlobalData), {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS}, .CPU_TO_GPU)
		frame.global_uniform_address.a = gfx.get_buffer_device_address(frame.global_uniform_buffer)

		// Model matrices
		frame.model_matrices_buffer = gfx.create_buffer(
			size_of(hlsl.float4x4) * 16_384,
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)
		frame.model_matrices_address.a = gfx.get_buffer_device_address(frame.model_matrices_buffer)

		// TODO: Skeletal mesh joint testing
		frame.test_joint_matrices_buffer = gfx.create_buffer(
			vk.DeviceSize(size_of(hlsl.float4x4) * game.skel.joint_count),
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)
		frame.test_joint_matrices_address.a = gfx.get_buffer_device_address(frame.test_joint_matrices_buffer)

		gfx.push_deletion_queue(
			&gfx.renderer().main_deletion_queue,
			frame.global_uniform_buffer.buffer,
			frame.global_uniform_buffer.allocation,
		)
		gfx.push_deletion_queue(
			&gfx.renderer().main_deletion_queue,
			frame.model_matrices_buffer.buffer,
			frame.model_matrices_buffer.allocation,
		)
		gfx.push_deletion_queue(
			&gfx.renderer().main_deletion_queue,
			frame.test_joint_matrices_buffer.buffer,
			frame.test_joint_matrices_buffer.allocation,
		)
	}

	// TODO: TEMP: GO AWAY?
	resize(&game.model_matrices, 16_384)
}

//// RENDERING
draw :: proc() {
	cmd := gfx.begin_command_buffer()

	update_buffers()

	// Begin shadow pass
	gfx.transition_image(cmd, game.shadow_depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	// draw_shadow_map(cmd)
	// End shadow pass

	// Clear
	gfx.transition_image(cmd, gfx.renderer().draw_image.image, .UNDEFINED, .GENERAL)
	draw_background(cmd)

	// Begin geometry pass
	// gfx.transition_image(cmd, &gfx.renderer().draw_image, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL)
	// gfx.transition_image(cmd, &gfx.renderer().depth_image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	// gfx.transition_image(cmd, &game.shadow_depth_image, .DEPTH_ATTACHMENT_OPTIMAL, .DEPTH_READ_ONLY_OPTIMAL)
	// draw_geometry(cmd)
	// End geometry pass

	// TODO: TEMP: Begin Skeletal mesh pass - This should be a skinning compute prepass instead.
	gfx.transition_image(cmd, gfx.renderer().draw_image.image, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL)
	gfx.transition_image(cmd, gfx.renderer().depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	gfx.transition_image(cmd, game.shadow_depth_image.image, .DEPTH_ATTACHMENT_OPTIMAL, .DEPTH_READ_ONLY_OPTIMAL)
	draw_skeletal_mesh(cmd)
	// End skeletal mesh pass

	// Begin post-processing pass
	gfx.transition_image(cmd, gfx.renderer().draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .GENERAL)
	post_processing_pass(cmd)
	// End post-processing pass

	if gfx.msaa_enabled() {
		ex := gfx.renderer().draw_extent

		// Resolve MSAA
		gfx.transition_image(cmd, gfx.renderer().draw_image.image, .GENERAL, .TRANSFER_SRC_OPTIMAL)
		gfx.transition_image(cmd, gfx.renderer().resolve_image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

		resolve_region := vk.ImageResolve {
			srcSubresource = {mipLevel = 0, aspectMask = {.COLOR}, baseArrayLayer = 0, layerCount = 1},
			srcOffset = {0, 0, 0},
			dstSubresource = {mipLevel = 0, aspectMask = {.COLOR}, baseArrayLayer = 0, layerCount = 1},
			dstOffset = {0, 0, 0},
			extent = {ex.width, ex.height, 1},
		}

		vk.CmdResolveImage(
			cmd,
			gfx.renderer().draw_image.image,
			.TRANSFER_SRC_OPTIMAL,
			gfx.renderer().resolve_image.image,
			.TRANSFER_DST_OPTIMAL,
			1,
			&resolve_region,
		)

		// Prepare swapchain image
		gfx.transition_image(cmd, gfx.renderer().resolve_image.image, .TRANSFER_DST_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
		gfx.copy_image_to_swapchain(cmd, gfx.renderer().resolve_image.image, gfx.renderer().draw_extent)
	} else {
		// Prepare swapchain image
		gfx.transition_image(cmd, gfx.renderer().draw_image.image, .GENERAL, .TRANSFER_SRC_OPTIMAL)
		gfx.copy_image_to_swapchain(cmd, gfx.renderer().draw_image.image, gfx.renderer().draw_extent)
	}

	gfx.submit(cmd)
}

draw_shadow_map :: proc(cmd: vk.CommandBuffer) {
	depth_attachment := gfx.init_attachment_info(
		game.shadow_depth_image.image_view,
		&{depthStencil = {depth = 1.0}},
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

	width := game.shadow_depth_image.extent.width
	height := game.shadow_depth_image.extent.height

	render_info := gfx.init_rendering_info({width, height}, nil, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	gfx.set_viewport_and_scissor(cmd, game.shadow_depth_image.extent)

	vk.CmdBindPipeline(cmd, .GRAPHICS, game.mesh_shadow_pipeline)
	{
		vk.CmdBindDescriptorSets(cmd, .GRAPHICS, game.mesh_pipeline_layout, 0, 1, &game.bindless_descriptor_set, 0, nil)
		vk.CmdBindIndexBuffer(cmd, game.sphere_mesh_buffers.index_buffer.buffer, 0, .UINT32)

		push_constants: GPUDrawPushConstants
		push_constants.vertex_buffer.a = game.sphere_mesh_buffers.vertex_address
		push_constants.global_data_buffer = current_frame_game().global_uniform_address
		push_constants.model_matrices = current_frame_game().model_matrices_address

		vk.CmdPushConstants(cmd, game.mesh_pipeline_layout, {.VERTEX, .FRAGMENT}, 0, size_of(GPUDrawPushConstants), &push_constants)

		vk.CmdDrawIndexed(cmd, game.sphere_mesh_buffers.index_count, 1, 0, 0, 0)
	}

	vk.CmdEndRendering(cmd)
}

draw_background :: proc(cmd: vk.CommandBuffer) {
	clear_color := vk.ClearColorValue {
		float32 = {0, 0, 0, 1},
	}

	clear_range := gfx.init_image_subresource_range({.COLOR})

	vk.CmdClearColorImage(cmd, gfx.renderer().draw_image.image, .GENERAL, &clear_color, 1, &clear_range)
}

draw_geometry :: proc(cmd: vk.CommandBuffer) {
	// begin a render pass  connected to our draw image
	color_attachment := gfx.init_attachment_info(gfx.renderer().draw_image.image_view, nil, .GENERAL)
	depth_attachment := gfx.init_attachment_info(
		gfx.renderer().depth_image.image_view,
		&{depthStencil = {depth = 1.0}},
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

	// Start render pass.
	render_info := gfx.init_rendering_info(gfx.renderer().draw_extent, &color_attachment, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	gfx.set_viewport_and_scissor(cmd, gfx.renderer().draw_extent)

	vk.CmdBindPipeline(cmd, .GRAPHICS, game.mesh_pipeline)
	{
		vk.CmdBindDescriptorSets(cmd, .GRAPHICS, game.mesh_pipeline_layout, 0, 1, &game.bindless_descriptor_set, 0, nil)
		vk.CmdBindIndexBuffer(cmd, game.sphere_mesh_buffers.index_buffer.buffer, 0, .UINT32)

		push_constants: GPUDrawPushConstants
		push_constants.vertex_buffer.a = game.sphere_mesh_buffers.vertex_address
		push_constants.global_data_buffer = current_frame_game().global_uniform_address
		push_constants.model_matrices = current_frame_game().model_matrices_address

		vk.CmdPushConstants(cmd, game.mesh_pipeline_layout, {.VERTEX, .FRAGMENT}, 0, size_of(GPUDrawPushConstants), &push_constants)

		// vk.CmdDrawIndexed(cmd, game.sphere_mesh_buffers.index_count, u32(len_entities(Ball)), 0, 0, 0)
	}

	vk.CmdEndRendering(cmd)
}

draw_skeletal_mesh :: proc(cmd: vk.CommandBuffer) {
	// begin a render pass  connected to our draw image
	color_attachment := gfx.init_attachment_info(gfx.renderer().draw_image.image_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
	depth_attachment := gfx.init_attachment_info(
		gfx.renderer().depth_image.image_view,
		&{depthStencil = {depth = 1.0}},
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

	// Start render pass.
	render_info := gfx.init_rendering_info(gfx.renderer().draw_extent, &color_attachment, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	gfx.set_viewport_and_scissor(cmd, gfx.renderer().draw_extent)

	vk.CmdBindPipeline(cmd, .GRAPHICS, game.skel_mesh_pipeline)
	{
		vk.CmdBindDescriptorSets(cmd, .GRAPHICS, game.skel_mesh_pipeline_layout, 0, 1, &game.bindless_descriptor_set, 0, nil)
		vk.CmdBindIndexBuffer(cmd, game.skel_mesh_buffers.index_buffer.buffer, 0, .UINT32)

		push_constants: GPUSkelDrawPushConstants
		push_constants.vertex_buffer.a = game.skel_mesh_buffers.vertex_address
		push_constants.global_data_buffer = current_frame_game().global_uniform_address
		push_constants.model_matrices = current_frame_game().model_matrices_address
		push_constants.joint_matrices = current_frame_game().test_joint_matrices_address
		push_constants.attrs.a = game.skel_mesh_buffers.skel_vert_attrs_address

		vk.CmdPushConstants(
			cmd,
			game.skel_mesh_pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			size_of(GPUSkelDrawPushConstants),
			&push_constants,
		)

		vk.CmdDrawIndexed(cmd, game.skel_mesh_buffers.index_count, 1, 0, 0, 0)
	}

	vk.CmdEndRendering(cmd)
}

post_processing_pass :: proc(cmd: vk.CommandBuffer) {
	vk.CmdBindPipeline(cmd, .COMPUTE, game.tonemapper_pipeline)
	vk.CmdBindDescriptorSets(cmd, .COMPUTE, game.tonemapper_pipeline_layout, 0, 1, &game.bindless_descriptor_set, 0, nil)

	vk.CmdDispatch(
		cmd,
		u32(math.ceil(f32(gfx.renderer().draw_extent.width) / 16.0)),
		u32(math.ceil(f32(gfx.renderer().draw_extent.height) / 16.0)),
		1,
	)
}

update_buffers :: proc() {
	global_uniform_data: GPUGlobalData

	camera := get_entity(game.state.camera_id)

	// Camera matrices
	{
		aspect_ratio := f32(gfx.renderer().window_extent.width) / f32(gfx.r_ctx.window_extent.height)

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

		global_uniform_data.view_projection_i_matrix = linalg.matrix4_inverse(global_uniform_data.view_projection_matrix)
	}

	// Global sun matrices
	{
		sun_view_matrix := linalg.matrix4_look_at_f32(game.state.environment.sun_pos, game.state.environment.sun_target, {0.0, 1.0, 0.0})
		sun_projection_matrix := gfx.matrix_ortho3d_z0_f32(-50, 50, -50, 50, 0.1, 500.0)
		sun_projection_matrix[1][1] *= -1.0

		global_uniform_data.sun_view_projection_matrix = sun_projection_matrix * sun_view_matrix

		global_uniform_data.view_projection_i_matrix = linalg.matrix4_inverse(global_uniform_data.view_projection_matrix)
	}

	global_uniform_data.sun_color = game.state.environment.sun_color
	global_uniform_data.sky_color = game.state.environment.sky_color
	global_uniform_data.bias = game.state.environment.bias

	global_uniform_data.camera_pos = hlsl.float3(camera != nil ? camera.translation : [3]f32{0, 0, 0})
	global_uniform_data.sun_pos = hlsl.float3(game.state.environment.sun_pos)

	gfx.write_buffer(&current_frame_game().global_uniform_buffer, &global_uniform_data)

	game.model_matrices[0] = linalg.identity(hlsl.float4x4)

	gfx.write_buffer_array(&current_frame_game().model_matrices_buffer, game.model_matrices[:])
	gfx.write_buffer_array(&current_frame_game().test_joint_matrices_buffer, game.skel_animator.calc_joints[:])
}
