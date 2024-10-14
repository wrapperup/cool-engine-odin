package gfx

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

import im_vk "deps:odin-imgui/imgui_impl_vulkan"

log_normal :: proc(args: ..any) {
	if r_ctx.enable_logs {
		fmt.println(args)
	}
}

log_error :: proc(args: ..any) {
	if r_ctx.enable_logs {
		fmt.println(args)
	}
}

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

r_ctx: Renderer

Renderer :: struct {
	debug_messenger:             vk.DebugUtilsMessengerEXT,
	enable_logs:                 bool,
	instance:                    vk.Instance,
	physical_device:             vk.PhysicalDevice,
	device:                      vk.Device,

	// Queues
	graphics_queue:              vk.Queue,
	graphics_queue_family:       u32,
	surface:                     vk.SurfaceKHR,

	// Swapchain
	swapchain:                   vk.SwapchainKHR,
	swapchain_images:            []vk.Image,
	swapchain_image_index:       u32,
	swapchain_image_views:       []vk.ImageView,
	swapchain_image_format:      vk.Format,
	swapchain_extent:            vk.Extent2D,

	// Command Pool/Buffer
	frames:                      [FRAME_OVERLAP]FrameData,
	frame_number:                int,
	main_deletion_queue:         DeletionQueue,
	allocator:                   vma.Allocator,

	// Draw resources
	draw_image:                  AllocatedImage,
	resolve_image:               AllocatedImage,
	depth_image:                 AllocatedImage,
	draw_extent:                 vk.Extent2D,
	msaa_samples:                vk.SampleCountFlag,

	// Descriptors
	global_descriptor_allocator: DescriptorAllocator,

	// Immediate submit
	imm_fence:                   vk.Fence,
	imm_command_buffer:          vk.CommandBuffer,
	imm_command_pool:            vk.CommandPool,

	// Dear Imgui
	imgui_init:                  bool,
	imgui_pool:                  vk.DescriptorPool,
}

FrameData :: struct {
	swapchain_semaphore, render_semaphore: vk.Semaphore,
	render_fence:                          vk.Fence,
	command_pool:                          vk.CommandPool,
	main_command_buffer:                   vk.CommandBuffer,
	deletion_queue:                        DeletionQueue,
}

SwapChainSupportDetails :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

begin_immediate_submit :: proc() -> vk.CommandBuffer {
	vk_check(vk.ResetFences(r_ctx.device, 1, &r_ctx.imm_fence))
	vk_check(vk.ResetCommandBuffer(r_ctx.imm_command_buffer, {}))

	cmd := r_ctx.imm_command_buffer

	cmd_begin_info := init_command_buffer_begin_info({.ONE_TIME_SUBMIT})

	vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info))

	return cmd
}

end_immediate_submit :: proc() {
	cmd := r_ctx.imm_command_buffer

	vk_check(vk.EndCommandBuffer(cmd))

	cmd_info := init_command_buffer_submit_info(cmd)
	submit := init_submit_info(&cmd_info, nil, nil)

	// submit command buffer to the queue and execute it.
	//  _renderFence will now block until the graphic commands finish execution
	vk_check(vk.QueueSubmit2(r_ctx.graphics_queue, 1, &submit, r_ctx.imm_fence))

	vk_check(vk.WaitForFences(r_ctx.device, 1, &r_ctx.imm_fence, true, 9_999_999_999))
}

@(deferred_in = end_immediate_submit)
immediate_submit :: proc() -> (cmd: vk.CommandBuffer, ready: bool) {
	return begin_immediate_submit(), true
}

current_frame_index :: proc() -> int {
	return r_ctx.frame_number % FRAME_OVERLAP
}

current_frame :: proc() -> ^FrameData {
	return &r_ctx.frames[current_frame_index()]
}

msaa_samples :: proc() -> vk.SampleCountFlag {
	return r_ctx.msaa_samples
}

msaa_enabled :: proc() -> bool {
	return r_ctx.msaa_samples > ._1
}

renderer :: proc() -> ^Renderer {
	return &r_ctx
}

delete_swapchain_support_details :: proc(details: SwapChainSupportDetails) {
	delete(details.formats)
	delete(details.present_modes)
}

init_global_descriptor_allocator :: proc() {
	//create a descriptor pool that will hold 10 sets with 1 image each
	ratio: f32 = 1.0 / 3.0
	sizes: []PoolSizeRatio = {{.SAMPLER, ratio}, {.SAMPLED_IMAGE, ratio}, {.STORAGE_IMAGE, ratio}}
	init_descriptor_allocator(&r_ctx.global_descriptor_allocator, r_ctx.device, 10, sizes, {.UPDATE_AFTER_BIND})
}

init_vulkan :: proc(config: InitConfig) -> bool {
	r_ctx.enable_logs = config.enable_logs

	// Begin bootstrapping
	create_instance(config.enable_validation_layers) or_return
	setup_debug_messenger(config.enable_validation_layers)
	create_surface(config.window)

	pick_physical_device()
	fetch_queues(r_ctx.physical_device)
	create_logical_device()

	init_vma()

	create_swapchain(config.window)

	if config.window != nil {
		x, y := glfw.GetWindowSize(config.window)
		create_draw_images({x, y}, config.msaa_samples)
	}

	init_commands()
	init_sync_structures()
	// End bootstrapping

	init_imgui(config.window)

	init_global_descriptor_allocator()

	return true
}

init_vma :: proc() {
	vulkan_functions := vma.create_vulkan_functions()

	allocator_info := vma.AllocatorCreateInfo {
		vulkanApiVersion = vk.API_VERSION_1_3,
		physicalDevice   = r_ctx.physical_device,
		device           = r_ctx.device,
		instance         = r_ctx.instance,
		flags            = {.BUFFER_DEVICE_ADDRESS},
		pVulkanFunctions = &vulkan_functions,
	}

	vma.CreateAllocator(&allocator_info, &r_ctx.allocator)
}

cleanup_vulkan :: proc() {
	vk.DeviceWaitIdle(r_ctx.device)

	if r_ctx.imgui_init {
		im_vk.Shutdown()
		vk.DestroyDescriptorPool(r_ctx.device, r_ctx.imgui_pool, nil)
	}

	// Cleanup queued resources
	flush_deletion_queue(&r_ctx.main_deletion_queue)
	delete_deletion_queue(r_ctx.main_deletion_queue)

	for &frame in r_ctx.frames {
		vk.DestroyCommandPool(r_ctx.device, frame.command_pool, nil)

		vk.DestroyFence(r_ctx.device, frame.render_fence, nil)
		vk.DestroySemaphore(r_ctx.device, frame.render_semaphore, nil)
		vk.DestroySemaphore(r_ctx.device, frame.swapchain_semaphore, nil)

		flush_deletion_queue(&frame.deletion_queue)
		delete_deletion_queue(frame.deletion_queue)
	}

	vk.DestroySwapchainKHR(r_ctx.device, r_ctx.swapchain, nil)

	// We don't need to delete the images, it was created by the driver
	// However, we did create the views, so we will destroy those now.
	for &image_view in &r_ctx.swapchain_image_views {
		vk.DestroyImageView(r_ctx.device, image_view, nil)
	}

	delete(r_ctx.swapchain_image_views)
	delete(r_ctx.swapchain_images)

	destroy_pools(&r_ctx.global_descriptor_allocator, r_ctx.device)
	destroy_descriptor_allocator(&r_ctx.global_descriptor_allocator)

	// Headless mode
	if r_ctx.surface != 0 {
		vk.DestroySurfaceKHR(r_ctx.instance, r_ctx.surface, nil)
	}

	vma.DestroyAllocator(r_ctx.allocator)
	vk.DestroyDevice(r_ctx.device, nil)

	if r_ctx.debug_messenger != 0 {
		vk.DestroyDebugUtilsMessengerEXT(r_ctx.instance, r_ctx.debug_messenger, nil)
	}

	vk.DestroyInstance(r_ctx.instance, nil)
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

LAST_WRITE: os.File_Time

is_shaders_updated :: proc() -> bool {
	lib_last_write, lib_last_write_err := os.last_write_time_by_name("./shaders/out/gradient.comp.spv")

	if LAST_WRITE == lib_last_write {
		return false
	}

	LAST_WRITE = lib_last_write

	return true
}

// Called by the user before they start drawing to the screen.
begin_command_buffer :: proc() -> vk.CommandBuffer {
	render_imgui()

	vk_check(vk.WaitForFences(r_ctx.device, 1, &current_frame().render_fence, true, 1_000_000_000))

	// Delete resources for the current frame
	flush_deletion_queue(&current_frame().deletion_queue)

	vk_check(
		vk.AcquireNextImageKHR(
			r_ctx.device,
			r_ctx.swapchain,
			1_000_000_000,
			current_frame().swapchain_semaphore,
			vk.Fence(0), // null
			&r_ctx.swapchain_image_index,
		),
	)

	r_ctx.draw_extent.width = r_ctx.draw_image.extent.width
	r_ctx.draw_extent.height = r_ctx.draw_image.extent.height

	vk_check(vk.ResetFences(r_ctx.device, 1, &current_frame().render_fence))

	// now that we are sure that the commands finished executing, we can safely
	// reset the command buffer to begin recording again.
	vk_check(vk.ResetCommandBuffer(current_frame().main_command_buffer, {.RELEASE_RESOURCES}))

	// naming it cmd for shorter writing
	cmd := current_frame().main_command_buffer

	// begin the command buffer recording. We will use this command buffer exactly once, so we want to let vulkan know that
	cmd_begin_info := init_command_buffer_begin_info({.ONE_TIME_SUBMIT})

	vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info))

	return cmd
}

copy_image_to_swapchain :: proc(cmd: vk.CommandBuffer, source: vk.Image, src_size: vk.Extent2D) {
	transition_image(cmd, r_ctx.swapchain_images[r_ctx.swapchain_image_index], .UNDEFINED, .TRANSFER_DST_OPTIMAL)

	copy_image_to_image(cmd, source, r_ctx.swapchain_images[r_ctx.swapchain_image_index], src_size, r_ctx.swapchain_extent)
}

// Called by the user when they end drawing to the screen.
submit :: proc(cmd: vk.CommandBuffer) {
	// set swapchain image layout to Attachment Optimal so we can draw it
	transition_image(cmd, r_ctx.swapchain_images[r_ctx.swapchain_image_index], .TRANSFER_DST_OPTIMAL, .COLOR_ATTACHMENT_OPTIMAL)

	//draw imgui into the swapchain image
	draw_imgui(cmd, r_ctx.swapchain_image_views[r_ctx.swapchain_image_index])

	// set swapchain image layout to Present so we can show it on the screen
	transition_image(cmd, r_ctx.swapchain_images[r_ctx.swapchain_image_index], .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR)

	//finalize the command buffer (we can no longer add commands, but it can now be executed)
	vk_check(vk.EndCommandBuffer(cmd))

	cmd_info := init_command_buffer_submit_info(cmd)

	wait_info := init_semaphore_submit_info({.COLOR_ATTACHMENT_OUTPUT}, current_frame().swapchain_semaphore)
	signal_info := init_semaphore_submit_info({.ALL_GRAPHICS}, current_frame().render_semaphore)

	submit := init_submit_info(&cmd_info, &signal_info, &wait_info)

	x := r_ctx.swapchain_image_index

	vk_check(vk.QueueSubmit2(r_ctx.graphics_queue, 1, &submit, current_frame().render_fence))

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		pSwapchains        = &r_ctx.swapchain,
		swapchainCount     = 1,
		pWaitSemaphores    = &current_frame().render_semaphore,
		waitSemaphoreCount = 1,
		pImageIndices      = &r_ctx.swapchain_image_index,
	}

	vk_check(vk.QueuePresentKHR(r_ctx.graphics_queue, &present_info))

	r_ctx.frame_number += 1
}

InitConfig :: struct {
	window:                   glfw.WindowHandle,
	msaa_samples:             vk.SampleCountFlag,
	enable_validation_layers: bool,
	enable_logs:              bool,
}

init :: proc(config := InitConfig{}) -> bool {
	init_vulkan(config) or_return

	return true
}

shutdown :: proc() {
	cleanup_vulkan()
}
