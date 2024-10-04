package gfx

import vk "vendor:vulkan"

import im "deps:odin-imgui"
import im_glfw "deps:odin-imgui/imgui_impl_glfw"
import im_vk "deps:odin-imgui/imgui_impl_vulkan"

init_imgui :: proc() {
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

	vk_check(vk.CreateDescriptorPool(r_ctx.device, &pool_info, nil, &r_ctx.imgui_pool))

	// 2: initialize imgui library

	// this initializes the core structures of imgui
	im.CreateContext()

	// this initializes imgui for glfw
	im_glfw.InitForVulkan(r_ctx.window, true)

	// this initializes imgui for Vulkan
	init_info := im_vk.InitInfo{}
	init_info.Instance = r_ctx.instance
	init_info.PhysicalDevice = r_ctx.physical_device
	init_info.Device = r_ctx.device
	init_info.Queue = r_ctx.graphics_queue
	init_info.DescriptorPool = r_ctx.imgui_pool
	init_info.MinImageCount = 3
	init_info.ImageCount = 3
	init_info.UseDynamicRendering = true
	init_info.ColorAttachmentFormat = r_ctx.swapchain_image_format
	init_info.MSAASamples = {._1}

	// We've already loaded the funcs with Odin's built-in loader,
	// imgui needs the addresses of those functions now.
	im_vk.LoadFunctions(proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
			return vk.GetInstanceProcAddr((cast(^vk.Instance)user_data)^, function_name)
		}, &r_ctx.instance)

	im_vk.Init(&init_info, 0)

	// execute a gpu command to upload imgui font textures
	// newer version of imgui automatically creates a command buffer,
	// and destroys the upload data, so we don't actually need to do anything else.
	im_vk.CreateFontsTexture()
}

render_imgui :: proc() {
	im.Render()
}

draw_imgui :: proc(cmd: vk.CommandBuffer, target_image_view: vk.ImageView) {
	color_attachment := init_attachment_info(target_image_view, nil, .GENERAL)
	render_info := init_rendering_info(r_ctx.swapchain_extent, &color_attachment, nil)

	vk.CmdBeginRendering(cmd, &render_info)

	im_vk.RenderDrawData(im.GetDrawData(), cmd)

	vk.CmdEndRendering(cmd)
}
