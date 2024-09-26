package renderer

import "base:runtime"
import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:strings"
import "core:time"

import vma "deps:odin-vma"
import "vendor:cgltf"
import "vendor:glfw"
import vk "vendor:vulkan"

import linalg "core:math/linalg"
import hlsl "core:math/linalg/hlsl"

import im "deps:odin-imgui"
import im_glfw "deps:odin-imgui/imgui_impl_glfw"
import im_vk "deps:odin-imgui/imgui_impl_vulkan"

vk_check :: proc(result: vk.Result, loc := #caller_location) {
	p := context.assertion_failure_proc
	if result != .SUCCESS {
		when ODIN_DEBUG {
			p("vk_check failed", reflect.enum_string(result), loc)
		} else {
			p("vk_check failed", "NOT SUCCESS", loc)
		}
	}
}

VulkanEngine :: struct {
	debug_messenger:              vk.DebugUtilsMessengerEXT,
	window:                       glfw.WindowHandle,
	window_extent:                vk.Extent2D,
	instance:                     vk.Instance,
	physical_device:              vk.PhysicalDevice,
	device:                       vk.Device,

	// Queues
	graphics_queue:               vk.Queue,
	graphics_queue_family:        u32,
	surface:                      vk.SurfaceKHR,

	// Swapchain
	swapchain:                    vk.SwapchainKHR,
	swapchain_images:             []vk.Image,
	swapchain_image_index:        u32,
	swapchain_image_views:        []vk.ImageView,
	swapchain_image_format:       vk.Format,
	swapchain_extent:             vk.Extent2D,

	// Command Pool/Buffer
	frames:                       [FRAME_OVERLAP]FrameData,
	frame_number:                 int,
	main_deletion_queue:          DeletionQueue,
	allocator:                    vma.Allocator,

	// Draw resources
	draw_image:                   AllocatedImage,
	depth_image:                  AllocatedImage,
	draw_extent:                  vk.Extent2D,

	// Descriptors
	global_descriptor_allocator:  DescriptorAllocator,
	draw_image_descriptor_set:    vk.DescriptorSet,
	draw_image_descriptor_layout: vk.DescriptorSetLayout,

	// Immediate submit
	imm_fence:                    vk.Fence,
	imm_command_buffer:           vk.CommandBuffer,
	imm_command_pool:             vk.CommandPool,

	// Dear Imgui
	imgui_pool:                   vk.DescriptorPool,

	// Stats
	frame_time_total:             f32,
	frame_time_game_state:        f32,
	frame_time_physics:           f32,
	frame_time_render:            f32,
	delta_time:                   f64,

	// TODO: App specific Mesh pipeline
	mesh_pipeline_layout:         vk.PipelineLayout,
	mesh_pipeline:                vk.Pipeline,
	mesh_descriptor_set:          vk.DescriptorSet,
	mesh_descriptor_layout:       vk.DescriptorSetLayout,
	model_matrices:               [dynamic]hlsl.float4x4,
	mesh_buffers:                 GPUMeshBuffers,
	sphere_mesh_buffers:          GPUMeshBuffers,
	TEMP_mesh_image:              AllocatedImage,
	TEMP_mesh_image_sampler:      vk.Sampler,

	// TODO: App specific Shadow mapping
	mesh_shadow_pipeline:         vk.Pipeline,
	shadow_depth_image:           AllocatedImage,
	shadow_depth_sampler:         vk.Sampler,
}

FrameData :: struct {
	swapchain_semaphore, render_semaphore: vk.Semaphore,
	render_fence:                          vk.Fence,
	command_pool:                          vk.CommandPool,
	main_command_buffer:                   vk.CommandBuffer,
	deletion_queue:                        DeletionQueue,

	// TODO: App specific Buffers, BDA
	global_uniform_buffer:                 AllocatedBuffer,
	global_uniform_address:                vk.DeviceAddress,
	model_matrices_buffer:                 AllocatedBuffer,
	model_matrices_address:                vk.DeviceAddress,
}

SwapChainSupportDetails :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

begin_immediate_submit :: proc(engine: ^VulkanEngine) -> vk.CommandBuffer {
	vk_check(vk.ResetFences(engine.device, 1, &engine.imm_fence))
	vk_check(vk.ResetCommandBuffer(engine.imm_command_buffer, {}))

	cmd := engine.imm_command_buffer

	cmd_begin_info := init_command_buffer_begin_info({.ONE_TIME_SUBMIT})

	vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info))

	return cmd
}

end_immediate_submit :: proc(engine: ^VulkanEngine) {
	cmd := engine.imm_command_buffer

	vk_check(vk.EndCommandBuffer(cmd))

	cmd_info := init_command_buffer_submit_info(cmd)
	submit := init_submit_info(&cmd_info, nil, nil)

	// submit command buffer to the queue and execute it.
	//  _renderFence will now block until the graphic commands finish execution
	vk_check(vk.QueueSubmit2(engine.graphics_queue, 1, &submit, engine.imm_fence))

	vk_check(vk.WaitForFences(engine.device, 1, &engine.imm_fence, true, 9_999_999_999))
}

@(deferred_in = end_immediate_submit)
immediate_submit :: proc(engine: ^VulkanEngine) -> (cmd: vk.CommandBuffer, ready: bool) {
	return begin_immediate_submit(engine), true
}

init_imgui :: proc(engine: ^VulkanEngine) {
	pool_sizes := []vk.DescriptorPoolSize {
		{.SAMPLER, 1000},
		{.COMBINED_IMAGE_SAMPLER, 1000},
		{.SAMPLED_IMAGE, 1000},
		{.STORAGE_IMAGE, 1000},
		{.UNIFORM_TEXEL_BUFFER, 1000},
		{.STORAGE_TEXEL_BUFFER, 1000},
		{.UNIFORM_BUFFER, 1000},
		{.STORAGE_BUFFER, 1000},
		{.UNIFORM_BUFFER_DYNAMIC, 1000},
		{.STORAGE_BUFFER_DYNAMIC, 1000},
		{.INPUT_ATTACHMENT, 1000},
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
	}
	pool_info.flags = {.FREE_DESCRIPTOR_SET}
	pool_info.maxSets = 1_000
	pool_info.poolSizeCount = u32(len(pool_sizes))
	pool_info.pPoolSizes = raw_data(pool_sizes)

	vk_check(vk.CreateDescriptorPool(engine.device, &pool_info, nil, &engine.imgui_pool))

	// 2: initialize imgui library

	// this initializes the core structures of imgui
	im.CreateContext()

	// this initializes imgui for glfw
	im_glfw.InitForVulkan(engine.window, true)

	// this initializes imgui for Vulkan
	init_info := im_vk.InitInfo{}
	init_info.Instance = engine.instance
	init_info.PhysicalDevice = engine.physical_device
	init_info.Device = engine.device
	init_info.Queue = engine.graphics_queue
	init_info.DescriptorPool = engine.imgui_pool
	init_info.MinImageCount = 3
	init_info.ImageCount = 3
	init_info.UseDynamicRendering = true
	init_info.ColorAttachmentFormat = engine.swapchain_image_format
	init_info.MSAASamples = {._1}

	// We've already loaded the funcs with Odin's built-in loader,
	// imgui needs the addresses of those functions now.
	im_vk.LoadFunctions(proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
			return vk.GetInstanceProcAddr((cast(^vk.Instance)user_data)^, function_name)
		}, &engine.instance)

	im_vk.Init(&init_info, 0)

	// execute a gpu command to upload imgui font textures
	// newer version of imgui automatically creates a command buffer,
	// and destroys the upload data, so we don't actually need to do anything else.
	im_vk.CreateFontsTexture()
}

current_frame :: proc(engine: ^VulkanEngine) -> ^FrameData {
	return &engine.frames[engine.frame_number % FRAME_OVERLAP]
}

delete_swapchain_support_details :: proc(details: SwapChainSupportDetails) {
	delete(details.formats)
	delete(details.present_modes)
}

// TODO: App specific.
create_shadow_map :: proc(engine: ^VulkanEngine, extent: vk.Extent3D) {
	img_alloc_info := vma.AllocationCreateInfo {
		usage         = .GPU_ONLY,
		requiredFlags = {.DEVICE_LOCAL},
	}

	engine.shadow_depth_image.format = .D32_SFLOAT
	engine.shadow_depth_image.extent = extent
	depth_image_usages := vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED}

	dimg_info := init_image_create_info(engine.shadow_depth_image.format, depth_image_usages, extent, ._1)

	//allocate and create the image
	vma.CreateImage(
		engine.allocator,
		&dimg_info,
		&img_alloc_info,
		&engine.shadow_depth_image.image,
		&engine.shadow_depth_image.allocation,
		nil,
	)

	//build a image-view for the draw image to use for rendering
	dview_info := init_imageview_create_info(
		engine.shadow_depth_image.format,
		engine.shadow_depth_image.image,
		{.DEPTH},
	)

	vk_check(vk.CreateImageView(engine.device, &dview_info, nil, &engine.shadow_depth_image.image_view))

	push_deletion_queue(&engine.main_deletion_queue, engine.shadow_depth_image.image_view)
	push_deletion_queue(
		&engine.main_deletion_queue,
		engine.shadow_depth_image.image,
		engine.shadow_depth_image.allocation,
	)
}

// TODO: App specific.
create_test_image :: proc(engine: ^VulkanEngine) {
	engine.TEMP_mesh_image = load_image_from_file(engine)
}

// TODO: App specific. Provide better abstraction for defining descriptor layouts?
init_descriptors :: proc(engine: ^VulkanEngine) {
	//create a descriptor pool that will hold 10 sets with 1 image each
	sizes: []PoolSizeRatio = {{.COMBINED_IMAGE_SAMPLER, 1}}

	init_descriptor_allocator(&engine.global_descriptor_allocator, engine.device, 10, sizes, {.UPDATE_AFTER_BIND})

	{
		engine.mesh_descriptor_layout = create_descriptor_set_layout(
			engine,
			[?]DescriptorBinding{{0, .COMBINED_IMAGE_SAMPLER}, {1, .COMBINED_IMAGE_SAMPLER}},
			{.VERTEX, .FRAGMENT},
		)
	}

	engine.mesh_descriptor_set = allocate_descriptor_set(
		&engine.global_descriptor_allocator,
		engine.device,
		engine.mesh_descriptor_layout,
	)

	push_deletion_queue(&engine.main_deletion_queue, engine.mesh_descriptor_layout)

	// Shadow Depth Texture Sampler
	{
		sampler_create_info := vk.SamplerCreateInfo {
			sType         = .SAMPLER_CREATE_INFO,
			magFilter     = .LINEAR,
			minFilter     = .LINEAR,
			mipmapMode    = .LINEAR,
			addressModeU  = .CLAMP_TO_EDGE,
			addressModeV  = .CLAMP_TO_EDGE,
			addressModeW  = .CLAMP_TO_EDGE,
			mipLodBias    = 0.0,
			maxAnisotropy = 1.0,
			minLod        = 0.0,
			maxLod        = 1.0,
			borderColor   = .INT_OPAQUE_WHITE,
			compareOp     = .LESS_OR_EQUAL,
			compareEnable = true,
		}

		vk_check(vk.CreateSampler(engine.device, &sampler_create_info, nil, &engine.shadow_depth_sampler))
		push_deletion_queue(&engine.main_deletion_queue, engine.shadow_depth_sampler)

		shadow_depth_image_info := vk.DescriptorImageInfo {
			imageLayout = .DEPTH_READ_ONLY_OPTIMAL,
			imageView   = engine.shadow_depth_image.image_view,
			sampler     = engine.shadow_depth_sampler,
		}

		shadow_depth_image_write := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			pNext           = nil,
			dstBinding      = 0,
			dstSet          = engine.mesh_descriptor_set,
			descriptorCount = 1,
			descriptorType  = .COMBINED_IMAGE_SAMPLER,
			pImageInfo      = &shadow_depth_image_info,
		}

		vk.UpdateDescriptorSets(engine.device, 1, &shadow_depth_image_write, 0, nil)
	}

	// Test Texture Sampler
	{
		sampler_create_info := vk.SamplerCreateInfo {
			sType        = .SAMPLER_CREATE_INFO,
			magFilter    = .LINEAR,
			minFilter    = .LINEAR,
			addressModeU = .CLAMP_TO_EDGE,
			addressModeV = .CLAMP_TO_EDGE,
			addressModeW = .CLAMP_TO_EDGE,
		}

		vk_check(vk.CreateSampler(engine.device, &sampler_create_info, nil, &engine.TEMP_mesh_image_sampler))
		push_deletion_queue(&engine.main_deletion_queue, engine.TEMP_mesh_image_sampler)

		test_image_info := vk.DescriptorImageInfo {
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
			imageView   = engine.TEMP_mesh_image.image_view,
			sampler     = engine.TEMP_mesh_image_sampler,
		}

		test_image_write := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			pNext           = nil,
			dstBinding      = 1,
			dstSet          = engine.mesh_descriptor_set,
			descriptorCount = 1,
			descriptorType  = .COMBINED_IMAGE_SAMPLER,
			pImageInfo      = &test_image_info,
		}

		vk.UpdateDescriptorSets(engine.device, 1, &test_image_write, 0, nil)
	}
}

// TODO: App specific.
init_pipelines :: proc(engine: ^VulkanEngine) {
	init_mesh_pipelines(engine)
}

// TODO: App specific.
init_mesh_pipelines :: proc(engine: ^VulkanEngine) {
	triangle_shader, f_ok := load_shader_module("shaders/out/shaders.spv", engine.device)

	if !f_ok {
		panic("flip")
	}

	{
		opts := cgltf.options{}
		data, ok := cgltf.parse_file(opts, "assets/bunny.glb")
		if ok != .success {
			panic("ASGASDGSDGSD")
		}
		if cgltf.load_buffers(opts, data, "assets/bunny.glb") != .success {
			panic("gnar")
		}
		defer cgltf.free(data)

		indices, vertices, parse_ok := temp_parse_mesh_into_mesh_data(data, 0)
		defer delete(indices)
		defer delete(vertices)

		if !parse_ok {
			panic("yuh")
		}

		engine.mesh_buffers = create_mesh_buffers(engine, indices, vertices)
		engine.mesh_buffers.index_count = u32(len(indices))
	}
	{
		opts := cgltf.options{}
		data, ok := cgltf.parse_file(opts, "assets/sphere.glb")
		if ok != .success {
			panic("ASGASDGSDGSD")
		}
		if cgltf.load_buffers(opts, data, "assets/sphere.glb") != .success {
			panic("gnar")
		}
		defer cgltf.free(data)

		indices, vertices, parse_ok := temp_parse_mesh_into_mesh_data(data, 0)
		defer delete(indices)
		defer delete(vertices)

		if !parse_ok {
			panic("yuh")
		}

		engine.sphere_mesh_buffers = create_mesh_buffers(engine, indices, vertices)
		engine.sphere_mesh_buffers.index_count = u32(len(indices))
	}


	buffer_range := vk.PushConstantRange {
		offset     = 0,
		size       = size_of(GPUDrawPushConstants),
		stageFlags = {.VERTEX, .FRAGMENT},
	}

	pipeline_layout_info := init_pipeline_layout_create_info()
	pipeline_layout_info.pPushConstantRanges = &buffer_range
	pipeline_layout_info.pushConstantRangeCount = 1
	pipeline_layout_info.pSetLayouts = &engine.mesh_descriptor_layout
	pipeline_layout_info.setLayoutCount = 1

	vk_check(vk.CreatePipelineLayout(engine.device, &pipeline_layout_info, nil, &engine.mesh_pipeline_layout))

	pipeline_builder := pb_init()
	defer pb_delete(pipeline_builder)

	pipeline_builder.pipeline_layout = engine.mesh_pipeline_layout
	pb_set_shaders(&pipeline_builder, triangle_shader)
	pb_set_input_topology(&pipeline_builder, .TRIANGLE_LIST)
	pb_set_polygon_mode(&pipeline_builder, .FILL)
	pb_set_cull_mode(&pipeline_builder, {.BACK}, .COUNTER_CLOCKWISE)
	pb_set_multisampling(&pipeline_builder, ._1)
	pb_disable_blending(&pipeline_builder)
	pb_enable_depthtest(&pipeline_builder, true, .LESS_OR_EQUAL)
	pb_set_color_attachment_format(&pipeline_builder, engine.draw_image.format)
	pb_set_depth_format(&pipeline_builder, engine.depth_image.format)

	engine.mesh_pipeline = pb_build_pipeline(&pipeline_builder, engine.device)

	pb_set_shaders(&pipeline_builder, triangle_shader, "vertex_shadow_main", "fragment_shadow_main")
	pb_disable_color_attachment(&pipeline_builder)
	engine.mesh_shadow_pipeline = pb_build_pipeline(&pipeline_builder, engine.device)

	vk.DestroyShaderModule(engine.device, triangle_shader, nil)

	push_deletion_queue(&engine.main_deletion_queue, engine.mesh_pipeline_layout)
	push_deletion_queue(&engine.main_deletion_queue, engine.mesh_pipeline)
	push_deletion_queue(&engine.main_deletion_queue, engine.mesh_shadow_pipeline)

	push_deletion_queue(
		&engine.main_deletion_queue,
		engine.mesh_buffers.index_buffer.buffer,
		engine.mesh_buffers.index_buffer.allocation,
	)
	push_deletion_queue(
		&engine.main_deletion_queue,
		engine.mesh_buffers.vertex_buffer.buffer,
		engine.mesh_buffers.vertex_buffer.allocation,
	)
}

// TODO: App specific.
init_buffers :: proc(engine: ^VulkanEngine) {
	for &frame in &engine.frames {
		// Global uniform buffer
		frame.global_uniform_buffer = create_buffer(
			engine,
			size_of(GPUGlobalData),
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)

		frame.global_uniform_address = get_buffer_device_address(engine, frame.global_uniform_buffer)

		// Model matrices
		frame.model_matrices_buffer = create_buffer(
			engine,
			size_of(hlsl.float4x4) * 16_384,
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)

		frame.model_matrices_address = get_buffer_device_address(engine, frame.model_matrices_buffer)

		push_deletion_queue(
			&engine.main_deletion_queue,
			frame.global_uniform_buffer.buffer,
			frame.global_uniform_buffer.allocation,
		)

		push_deletion_queue(
			&engine.main_deletion_queue,
			frame.model_matrices_buffer.buffer,
			frame.model_matrices_buffer.allocation,
		)
	}

	// TODO: TEMP: GO AWAY?
	resize(&engine.model_matrices, 16_384)
}

init_vulkan :: proc(engine: ^VulkanEngine) -> bool {
	// Begin bootstrapping
	create_instance(engine) or_return
	setup_debug_messenger(engine)
	create_surface(engine)

	pick_physical_device(engine)
	fetch_queues(engine, engine.physical_device)
	create_logical_device(engine)

	init_vma(engine)

	create_swapchain(engine)
	create_image_views(engine)

	init_commands(engine)
	init_sync_structures(engine)
	// End bootstrapping

	create_shadow_map(engine, {1024, 1024, 1})
	create_test_image(engine)

	init_descriptors(engine)
	init_pipelines(engine)

	init_imgui(engine)

	// TODO: App specific.
	init_buffers(engine)

	return true
}

init_vma :: proc(engine: ^VulkanEngine) {
	vulkan_functions := vma.create_vulkan_functions()

	allocator_info := vma.AllocatorCreateInfo {
		vulkanApiVersion = vk.API_VERSION_1_3,
		physicalDevice   = engine.physical_device,
		device           = engine.device,
		instance         = engine.instance,
		flags            = {.BUFFER_DEVICE_ADDRESS},
		pVulkanFunctions = &vulkan_functions,
	}

	vma.CreateAllocator(&allocator_info, &engine.allocator)
}

cleanup_window :: proc(engine: ^VulkanEngine) {
	glfw.DestroyWindow(engine.window)
	glfw.Terminate()
}

cleanup_vulkan :: proc(engine: ^VulkanEngine) {
	vk.DeviceWaitIdle(engine.device)

	im_vk.Shutdown()
	vk.DestroyDescriptorPool(engine.device, engine.imgui_pool, nil)

	// Cleanup queued resources
	flush_deletion_queue(engine, &engine.main_deletion_queue)
	delete_deletion_queue(engine.main_deletion_queue)

	for &frame in engine.frames {
		vk.DestroyCommandPool(engine.device, frame.command_pool, nil)

		vk.DestroyFence(engine.device, frame.render_fence, nil)
		vk.DestroySemaphore(engine.device, frame.render_semaphore, nil)
		vk.DestroySemaphore(engine.device, frame.swapchain_semaphore, nil)

		flush_deletion_queue(engine, &frame.deletion_queue)
		delete_deletion_queue(frame.deletion_queue)
	}

	vk.DestroySwapchainKHR(engine.device, engine.swapchain, nil)

	// We don't need to delete the images, it was created by the driver
	// However, we did create the views, so we will destroy those now.
	for &image_view in &engine.swapchain_image_views {
		vk.DestroyImageView(engine.device, image_view, nil)
	}

	delete(engine.swapchain_image_views)
	delete(engine.swapchain_images)

	destroy_pools(&engine.global_descriptor_allocator, engine.device)
	destroy_descriptor_allocator(&engine.global_descriptor_allocator)	

	vk.DestroySurfaceKHR(engine.instance, engine.surface, nil)

	vma.DestroyAllocator(engine.allocator)

	vk.DestroyDevice(engine.device, nil)
	vk.DestroyDebugUtilsMessengerEXT(engine.instance, engine.debug_messenger, nil)
	vk.DestroyInstance(engine.instance, nil)
}

render_imgui :: proc(engine: ^VulkanEngine) {
	im.Render()
}

render :: proc(engine: ^VulkanEngine) {
	render_imgui(engine)

	cmd := begin_draw(engine)
	draw(engine, cmd)
	draw_end(engine, cmd)
}

draw_imgui :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer, target_image_view: vk.ImageView) {
	color_attachment := init_attachment_info(target_image_view, nil, .GENERAL)
	render_info := init_rendering_info(engine.swapchain_extent, &color_attachment, nil)

	vk.CmdBeginRendering(cmd, &render_info)

	im_vk.RenderDrawData(im.GetDrawData(), cmd)

	vk.CmdEndRendering(cmd)
}

draw_background :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) {
	clear_color := vk.ClearColorValue {
		float32 = {0, 0, 0, 1},
	}

	clear_range := init_image_subresource_range({.COLOR})

	vk.CmdClearColorImage(cmd, engine.draw_image.image, .GENERAL, &clear_color, 1, &clear_range)
}

set_viewport_and_scissor_2d :: proc(cmd: vk.CommandBuffer, extent: vk.Extent2D) {
	set_viewport_and_scissor_3d(cmd, {extent.width, extent.height, 1})
}

set_viewport_and_scissor_3d :: proc(cmd: vk.CommandBuffer, extent: vk.Extent3D) {
	//set dynamic viewport and scissor
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(extent.width),
		height   = f32(extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {x = 0, y = 0},
		extent = {extent.width, extent.height},
	}

	vk.CmdSetScissor(cmd, 0, 1, &scissor)
}

set_viewport_and_scissor :: proc {
	set_viewport_and_scissor_3d,
	set_viewport_and_scissor_2d,
}

draw_shadow_map :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) {
	//begin a render pass  connected to our draw image
	depth_attachment := init_depth_attachment_info(engine.shadow_depth_image.image_view, .DEPTH_ATTACHMENT_OPTIMAL)

	width := engine.shadow_depth_image.extent.width
	height := engine.shadow_depth_image.extent.height

	render_info := init_rendering_info({width, height}, nil, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	set_viewport_and_scissor(cmd, engine.shadow_depth_image.extent)

	vk.CmdBindPipeline(cmd, .GRAPHICS, engine.mesh_shadow_pipeline)

	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, engine.mesh_pipeline_layout, 0, 1, &engine.mesh_descriptor_set, 0, nil)
	vk.CmdBindIndexBuffer(cmd, engine.sphere_mesh_buffers.index_buffer.buffer, 0, .UINT32)

	push_constants: GPUDrawPushConstants
	push_constants.vertex_buffer_address = engine.sphere_mesh_buffers.vertex_buffer_address
	push_constants.global_data_buffer_address = current_frame(engine).global_uniform_address
	push_constants.model_matrices_address = current_frame(engine).model_matrices_address

	vk.CmdPushConstants(
		cmd,
		engine.mesh_pipeline_layout,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(GPUDrawPushConstants),
		&push_constants,
	)

	// vk.CmdDrawIndexed(cmd, engine.sphere_mesh_buffers.index_count, u32(len_entities(Ball)), 0, 0, 0)

	vk.CmdEndRendering(cmd)
}

draw_geometry :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) {
	// TODO: Don't create each frame.
	//begin a render pass  connected to our draw image
	color_attachment := init_attachment_info(engine.draw_image.image_view, nil, .GENERAL)
	depth_attachment := init_depth_attachment_info(engine.depth_image.image_view, .DEPTH_ATTACHMENT_OPTIMAL)

	render_info := init_rendering_info(engine.draw_extent, &color_attachment, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	set_viewport_and_scissor(cmd, engine.draw_extent)

	vk.CmdBindPipeline(cmd, .GRAPHICS, engine.mesh_pipeline)

	{
		vk.CmdBindDescriptorSets(
			cmd,
			.GRAPHICS,
			engine.mesh_pipeline_layout,
			0,
			1,
			&engine.mesh_descriptor_set,
			0,
			nil,
		)
		vk.CmdBindIndexBuffer(cmd, engine.sphere_mesh_buffers.index_buffer.buffer, 0, .UINT32)

		push_constants: GPUDrawPushConstants
		push_constants.vertex_buffer_address = engine.sphere_mesh_buffers.vertex_buffer_address
		push_constants.global_data_buffer_address = current_frame(engine).global_uniform_address
		push_constants.model_matrices_address = current_frame(engine).model_matrices_address

		vk.CmdPushConstants(
			cmd,
			engine.mesh_pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			size_of(GPUDrawPushConstants),
			&push_constants,
		)

		// vk.CmdDrawIndexed(cmd, engine.sphere_mesh_buffers.index_count, u32(len_entities(Ball)), 0, 0, 0)
	}

	vk.CmdEndRendering(cmd)
}

LAST_WRITE: os.File_Time

is_shaders_updated :: proc() -> bool {
	lib_last_write, lib_last_write_err := os.last_write_time_by_name("./shaders/out/gradient.comp.spv")

	if LAST_WRITE == lib_last_write {
		return false
	}

	LAST_WRITE = lib_last_write

	return true
}

update_buffers :: proc(engine: ^VulkanEngine) {
	global_uniform_data: GPUGlobalData

	// camera := get_entity(game_state.camera_id)
	//
	// // Camera matrices
	// {
	// 	aspect_ratio := f32(engine.window_extent.width) / f32(engine.window_extent.height)
	//
	// 	translation := linalg.matrix4_translate(camera != nil ? camera.translation : {})
	// 	rotation := linalg.matrix4_from_quaternion(camera != nil ? camera.rotation : {})
	//
	// 	view_matrix := linalg.inverse(linalg.mul(translation, rotation))
	//
	// 	// view_matrix := linalg.matrix4_look_at_f32(game_state.camera_pos, {0, 0, 0}, {0, 1, 0})
	//
	// 	projection_matrix := matrix4_infinite_perspective_z0_f32(
	// 		linalg.to_radians(camera != nil ? camera.camera_fov_deg : 0),
	// 		aspect_ratio,
	// 		0.1,
	// 	)
	// 	projection_matrix[1][1] *= -1.0
	//
	// 	global_uniform_data.view_projection_matrix = projection_matrix * view_matrix
	//
	// 	global_uniform_data.view_projection_i_matrix = linalg.matrix4_inverse(
	// 		global_uniform_data.view_projection_matrix,
	// 	)
	// }
	//
	// // Global sun matrices
	// {
	// 	sun_view_matrix := linalg.matrix4_look_at_f32(
	// 		game_state.environment.sun_pos,
	// 		game_state.environment.sun_target,
	// 		{0.0, 1.0, 0.0},
	// 	)
	// 	sun_projection_matrix := matrix_ortho3d_z0_f32(-50, 50, -50, 50, 0.1, 500.0)
	// 	sun_projection_matrix[1][1] *= -1.0
	//
	// 	global_uniform_data.sun_view_projection_matrix = sun_projection_matrix * sun_view_matrix
	//
	// 	global_uniform_data.view_projection_i_matrix = linalg.matrix4_inverse(
	// 		global_uniform_data.view_projection_matrix,
	// 	)
	// }
	//
	// global_uniform_data.sun_color = game_state.environment.sun_color
	// global_uniform_data.sky_color = game_state.environment.sky_color
	// global_uniform_data.bias = game_state.environment.bias
	//
	// global_uniform_data.camera_pos = hlsl.float3(camera != nil ? camera.translation : [3]f32{0, 0, 0})
	// global_uniform_data.sun_pos = hlsl.float3(game_state.environment.sun_pos)

	write_buffer(&current_frame(engine).global_uniform_buffer, &global_uniform_data)

	// parallel_for_entities(proc(entity: ^Ball, index: int, data: rawptr) {
	// 		model_matrices := transmute(^[dynamic]hlsl.float4x4)data
	//
	// 		translation := linalg.matrix4_translate(entity.translation)
	// 		rotation := linalg.matrix4_from_quaternion(entity.rotation)
	//
	// 		model_matrices[index] = linalg.mul(translation, rotation)
	// 	}, &engine.model_matrices)

	write_buffer_array(&current_frame(engine).model_matrices_buffer, engine.model_matrices[:])
}

begin_draw :: proc(engine: ^VulkanEngine) -> vk.CommandBuffer {
	vk_check(vk.WaitForFences(engine.device, 1, &current_frame(engine).render_fence, true, 1_000_000_000))

	// Delete resources for the current frame
	flush_deletion_queue(engine, &current_frame(engine).deletion_queue)

	when ODIN_DEBUG {
		if is_shaders_updated() {
			fmt.println("Updating shader module")
			init_pipelines(engine)
		}
	}

	update_buffers(engine)

	vk_check(
		vk.AcquireNextImageKHR(
			engine.device,
			engine.swapchain,
			1_000_000_000,
			current_frame(engine).swapchain_semaphore,
			vk.Fence(0), // null
			&engine.swapchain_image_index,
		),
	)

	engine.draw_extent.width = engine.draw_image.extent.width
	engine.draw_extent.height = engine.draw_image.extent.height

	vk_check(vk.ResetFences(engine.device, 1, &current_frame(engine).render_fence))

	// now that we are sure that the commands finished executing, we can safely
	// reset the command buffer to begin recording again.
	vk_check(vk.ResetCommandBuffer(current_frame(engine).main_command_buffer, {.RELEASE_RESOURCES}))

	//naming it cmd for shorter writing
	cmd := current_frame(engine).main_command_buffer

	//begin the command buffer recording. We will use this command buffer exactly once, so we want to let vulkan know that
	cmd_begin_info := init_command_buffer_begin_info({.ONE_TIME_SUBMIT})

	vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info))

	// transition our main draw image into general layout so we can write into it
	// we will overwrite it all so we dont care about what was the older layout
	transition_image(cmd, engine.draw_image.image, .UNDEFINED, .GENERAL)

	return cmd
}

// TODO: App specific.
draw :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) {
	draw_background(engine, cmd)

	// Begin shadow pass
	transition_image(cmd, engine.shadow_depth_image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	draw_shadow_map(engine, cmd)
	// End shadow pass

	// Begin geometry pass
	transition_image(cmd, engine.draw_image, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL)
	transition_image(cmd, engine.depth_image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	draw_geometry(engine, cmd)
	// End geometry pass

	// Prepare swapchain image
	transition_image(cmd, engine.draw_image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
	transition_image(cmd, engine.swapchain_images[engine.swapchain_image_index], .UNDEFINED, .TRANSFER_DST_OPTIMAL)

	// execute a copy from the draw image into the swapchain
	copy_image_to_image(
		cmd,
		engine.draw_image.image,
		engine.swapchain_images[engine.swapchain_image_index],
		engine.draw_extent,
		engine.swapchain_extent,
	)

	// set swapchain image layout to Attachment Optimal so we can draw it
	transition_image(
		cmd,
		engine.swapchain_images[engine.swapchain_image_index],
		.TRANSFER_DST_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
	)

	//draw imgui into the swapchain image
	draw_imgui(engine, cmd, engine.swapchain_image_views[engine.swapchain_image_index])

	// set swapchain image layout to Present so we can show it on the screen
	transition_image(
		cmd,
		engine.swapchain_images[engine.swapchain_image_index],
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
	)
}

draw_end :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) {
	//finalize the command buffer (we can no longer add commands, but it can now be executed)
	vk_check(vk.EndCommandBuffer(cmd))

	cmd_info := init_command_buffer_submit_info(cmd)

	wait_info := init_semaphore_submit_info({.COLOR_ATTACHMENT_OUTPUT}, current_frame(engine).swapchain_semaphore)
	signal_info := init_semaphore_submit_info({.ALL_GRAPHICS}, current_frame(engine).render_semaphore)

	submit := init_submit_info(&cmd_info, &signal_info, &wait_info)

	vk_check(vk.QueueSubmit2(engine.graphics_queue, 1, &submit, current_frame(engine).render_fence))

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		pSwapchains        = &engine.swapchain,
		swapchainCount     = 1,
		pWaitSemaphores    = &current_frame(engine).render_semaphore,
		waitSemaphoreCount = 1,
		pImageIndices      = &engine.swapchain_image_index,
	}

	vk_check(vk.QueuePresentKHR(engine.graphics_queue, &present_info))

	engine.frame_number += 1
}

init :: proc(engine: ^VulkanEngine) -> bool {
	init_window(engine) or_return
	init_vulkan(engine) or_return

	return true
}

shutdown :: proc(engine: ^VulkanEngine) {
	cleanup_vulkan(engine)
	cleanup_window(engine)
}
