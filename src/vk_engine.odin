package main

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
	shadow_depth_image:           AllocatedImage,
	shadow_depth_sampler:         vk.Sampler,
	draw_extent:                  vk.Extent2D,

	// Descriptors
	global_descriptor_allocator:  DescriptorAllocator,
	draw_image_descriptors:       vk.DescriptorSet,
	draw_image_descriptor_layout: vk.DescriptorSetLayout,

	// Immediate submit
	imm_fence:                    vk.Fence,
	imm_command_buffer:           vk.CommandBuffer,
	imm_command_pool:             vk.CommandPool,

	// Dear Imgui
	imgui_pool:                   vk.DescriptorPool,

	// Mesh Compute pipeline
	mesh_compute_pipeline:        vk.Pipeline,
	draw_pipeline_layout:         vk.PipelineLayout,
	draw_pipeline:                vk.Pipeline,

	// Mesh pipeline
	mesh_pipeline_layout:         vk.PipelineLayout,
	mesh_pipeline:                vk.Pipeline,
	mesh_shadow_pipeline:         vk.Pipeline,
	mesh_buffers:                 GPUMeshBuffers,
	mesh_indices_count:           u32,
	mesh_descriptors:             vk.DescriptorSet,
	mesh_descriptor_layout:       vk.DescriptorSetLayout,

	// Stats
	frame_time:                   f32,
	delta_time:                   f64,
	tri_count:                    u32,
}

FrameData :: struct {
	swapchain_semaphore, render_semaphore: vk.Semaphore,
	render_fence:                          vk.Fence,
	command_pool:                          vk.CommandPool,
	main_command_buffer:                   vk.CommandBuffer,
	deletion_queue:                        DeletionQueue,
	global_uniform_buffer:                 AllocatedBuffer,
	global_uniform_address:                vk.DeviceAddress,
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

fetch_queues :: proc(engine: ^VulkanEngine, device: vk.PhysicalDevice) -> bool {
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, raw_data(queue_families))

	has_graphics := false

	for queue_family, i in &queue_families {
		if .GRAPHICS in queue_family.queueFlags {
			engine.graphics_queue_family = u32(i)
			has_graphics = true
		}
	}

	return has_graphics
}

// This allocates format and present_mode slices.
query_swapchain_support :: proc(engine: ^VulkanEngine, device: vk.PhysicalDevice) -> SwapChainSupportDetails {
	details: SwapChainSupportDetails

	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, engine.surface, &details.capabilities)

	{
		format_count: u32
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, engine.surface, &format_count, nil)

		formats := make([]vk.SurfaceFormatKHR, format_count)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, engine.surface, &format_count, raw_data(formats))

		details.formats = formats
	}

	{
		present_mode_count: u32
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, engine.surface, &present_mode_count, nil)

		present_modes := make([]vk.PresentModeKHR, present_mode_count)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device,
			engine.surface,
			&present_mode_count,
			raw_data(present_modes),
		)

		details.present_modes = present_modes
	}

	return details
}

// This returns true if a surface format was found that matches the requirements.
// Otherwise, this returns the first surface format and false if one wasn't found.
choose_swap_surface_format :: proc(available_formats: []vk.SurfaceFormatKHR) -> (vk.SurfaceFormatKHR, bool) {
	for surface_format in available_formats {
		if surface_format.format == .B8G8R8A8_UNORM && surface_format.colorSpace == .SRGB_NONLINEAR {
			return surface_format, true
		}
	}

	return available_formats[0], false
}

choose_swap_present_mode :: proc(available_present_modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	return .IMMEDIATE
}

choose_swap_extent :: proc(engine: ^VulkanEngine, capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
	if (capabilities.currentExtent.width != max(u32)) {
		return capabilities.currentExtent
	} else {
		width, height := glfw.GetFramebufferSize(engine.window)

		actual_extent := vk.Extent2D{u32(width), u32(height)}

		actual_extent.width = clamp(
			actual_extent.width,
			capabilities.minImageExtent.width,
			capabilities.maxImageExtent.width,
		)
		actual_extent.height = clamp(
			actual_extent.height,
			capabilities.minImageExtent.height,
			capabilities.maxImageExtent.height,
		)

		return actual_extent
	}
}

supports_required_features :: proc(required: $T, test: T) -> bool {
	required := required
	test := test

	id := typeid_of(T)
	names := reflect.struct_field_names(id)
	types := reflect.struct_field_types(id)
	offsets := reflect.struct_field_offsets(id)

	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, " - ")
	reflect.write_type(&builder, type_info_of(T))
	strings.write_string(&builder, "\n")

	has_any_flags := false
	supports_all_flags := true

	for i in 0 ..< len(offsets) {
		// The flags are of type boolean
		if reflect.type_kind(types[i].id) == .Boolean {
			offset := offsets[i]

			// Grab the values at the offsets
			required_value := (cast(^b32)(uintptr(&required) + offset))^
			test_value := (cast(^b32)(uintptr(&test) + offset))^

			// Check if the flag is required
			if required_value {
				strings.write_string(&builder, "   + ")
				strings.write_string(&builder, names[i])

				// Returns false if the test doesn't have the required flag.
				if required_value != test_value {
					strings.write_string(&builder, " \xE2\x9D\x8C\n")
					supports_all_flags = false
				} else {
					strings.write_string(&builder, " \xE2\x9C\x94\n")
					has_any_flags = true
				}
			}
		}
	}

	if has_any_flags {
		fmt.print(strings.to_string(builder))
	}

	return supports_all_flags
}

is_device_suitable :: proc(engine: ^VulkanEngine, device: vk.PhysicalDevice) -> bool {
	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(device, &properties)

	vk_13_features := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
	}

	vk_12_features := vk.PhysicalDeviceVulkan12Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext = &vk_13_features,
	}

	vk_11_features := vk.PhysicalDeviceVulkan11Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		pNext = &vk_12_features,
	}

	features := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &vk_11_features,
	}

	vk.GetPhysicalDeviceFeatures2(device, &features)

	fmt.printfln("Required Features:")
	supports_features :=
		supports_required_features(REQUIRED_FEATURES, features) &&
		supports_required_features(REQUIRED_VK_11_FEATURES, vk_11_features) &&
		supports_required_features(REQUIRED_VK_12_FEATURES, vk_12_features) &&
		supports_required_features(REQUIRED_VK_13_FEATURES, vk_13_features)

	extensions_supported := check_device_extension_support(device)

	swapchain_adequate := false
	if extensions_supported {
		swapchain_support := query_swapchain_support(engine, device)
		defer delete_swapchain_support_details(swapchain_support)

		swapchain_adequate = len(swapchain_support.formats) > 0 && len(swapchain_support.present_modes) > 0
	}

	return swapchain_adequate && extensions_supported && properties.deviceType == .DISCRETE_GPU && supports_features
}

check_device_extension_support :: proc(device: vk.PhysicalDevice) -> bool {
	extension_count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil)

	available_extensions := make([]vk.ExtensionProperties, extension_count)
	defer delete(available_extensions)
	vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, raw_data(available_extensions))

	for &expected_extension in DEVICE_EXTENSIONS {
		found := false

		for available in &available_extensions {
			if libc.strcmp(cstring(&available.extensionName[0]), expected_extension) == 0 {
				found = true
				break
			}
		}

		found or_return
	}

	return true
}

create_surface :: proc(engine: ^VulkanEngine) {
	vk_check(glfw.CreateWindowSurface(engine.instance, engine.window, nil, &engine.surface))
}

init_window :: proc(engine: ^VulkanEngine) -> bool {
	glfw.Init()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	engine.window = glfw.CreateWindow(
		i32(engine.window_extent.width),
		i32(engine.window_extent.height),
		"Vulkan",
		nil,
		nil,
	)

	return true
}

debug_callback :: proc "system" (
	message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	message_types: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	context = runtime.default_context()
	fmt.println(callback_data.pMessage)

	return false
}

setup_debug_messenger :: proc(engine: ^VulkanEngine) {
	if ENABLE_VALIDATION_LAYERS {
		fmt.println("Creating Debug Messenger")
		create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE, .WARNING, .INFO, .ERROR},
			messageType     = {.GENERAL, .VALIDATION},
			pfnUserCallback = debug_callback,
			pUserData       = nil,
		}

		vk_check(vk.CreateDebugUtilsMessengerEXT(engine.instance, &create_info, nil, &engine.debug_messenger))
	}
}

check_validation_layers :: proc() -> bool {
	layer_count: u32 = 0
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)

	available_layers := make([]vk.LayerProperties, layer_count)
	defer delete(available_layers)
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

	for layer_name in VALIDATION_LAYERS {
		layer_found := false

		for layer_property in &available_layers {
			if libc.strcmp(layer_name, cstring(&layer_property.layerName[0])) == 0 {
				layer_found = true
				break
			}
		}

		layer_found or_return
	}


	return true
}

get_required_extensions :: proc() -> [dynamic]cstring {
	glfw_extensions := glfw.GetRequiredInstanceExtensions()

	extension_count := len(glfw_extensions)

	extensions: [dynamic]cstring
	resize(&extensions, extension_count)

	for ext, i in glfw_extensions {
		extensions[i] = ext
	}

	if ENABLE_VALIDATION_LAYERS {
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	return extensions
}

create_instance :: proc(engine: ^VulkanEngine) -> bool {
	// Loads vulkan api functions needed to create an instance
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	if ENABLE_VALIDATION_LAYERS && !check_validation_layers() {
		panic("validation layers are not available")
	}

	app_info := vk.ApplicationInfo{}
	app_info.sType = .APPLICATION_INFO
	app_info.pApplicationName = "Hello Triangle"
	app_info.applicationVersion = vk.MAKE_VERSION(0, 0, 1)
	app_info.pEngineName = "No Engine"
	app_info.engineVersion = vk.MAKE_VERSION(1, 0, 0)
	app_info.apiVersion = vk.API_VERSION_1_3

	create_info: vk.InstanceCreateInfo
	create_info.sType = .INSTANCE_CREATE_INFO
	create_info.pApplicationInfo = &app_info

	extensions := get_required_extensions()
	defer delete(extensions)

	create_info.ppEnabledExtensionNames = raw_data(extensions)
	create_info.enabledExtensionCount = cast(u32)len(extensions)

	debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT{}
	validation_features := vk.ValidationFeaturesEXT {
		sType                         = .VALIDATION_FEATURES_EXT,
		pEnabledValidationFeatures    = raw_data(VALIDATION_FEATURES),
		enabledValidationFeatureCount = u32(len(VALIDATION_LAYERS)),
	}

	if ENABLE_VALIDATION_LAYERS {
		create_info.enabledLayerCount = u32(len(VALIDATION_LAYERS))
		create_info.ppEnabledLayerNames = raw_data(VALIDATION_LAYERS)

		debug_create_info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
		debug_create_info.messageSeverity = {.WARNING, .ERROR, .INFO}
		debug_create_info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
		debug_create_info.pfnUserCallback = debug_callback
		debug_create_info.pNext = &validation_features

		create_info.pNext = &debug_create_info
	} else {
		create_info.enabledLayerCount = 0
		create_info.pNext = nil
	}

	vk_check(vk.CreateInstance(&create_info, nil, &engine.instance))

	// Load instance-specific procedures
	vk.load_proc_addresses_instance(engine.instance)

	n_ext: u32
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, nil)

	extension_props := make([]vk.ExtensionProperties, n_ext)
	defer delete(extension_props)

	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, raw_data(extension_props))

	fmt.println("Available Extensions:")

	bytes, ok := os.read_entire_file("")

	for ext in &extension_props {
		fmt.printfln(" - %s", cstring(&ext.extensionName[0]))
	}

	if ENABLE_VALIDATION_LAYERS && !check_validation_layers() {
		panic("Validation layers are not available")
	}

	return true
}

pick_physical_device :: proc(engine: ^VulkanEngine) {
	device_count: u32 = 0

	vk.EnumeratePhysicalDevices(engine.instance, &device_count, nil)

	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(engine.instance, &device_count, raw_data(devices))

	for device in devices {
		if is_device_suitable(engine, device) {
			engine.physical_device = device
			break
		}
	}

	if engine.physical_device == nil {
		panic("No GPU found that supports all required features.")
	}
}

create_logical_device :: proc(engine: ^VulkanEngine) {
	queue_priority: f32 = 1.0

	queue_create_info: vk.DeviceQueueCreateInfo
	queue_create_info.sType = .DEVICE_QUEUE_CREATE_INFO
	queue_create_info.queueFamilyIndex = engine.graphics_queue_family
	queue_create_info.queueCount = 1
	queue_create_info.pQueuePriorities = &queue_priority

	device_create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &REQUIRED_FEATURES,
		pQueueCreateInfos       = &queue_create_info,
		queueCreateInfoCount    = 1,
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
	}

	vk_check(vk.CreateDevice(engine.physical_device, &device_create_info, nil, &engine.device))

	vk.GetDeviceQueue(engine.device, engine.graphics_queue_family, 0, &engine.graphics_queue)
}

init_commands :: proc(engine: ^VulkanEngine) {
	command_pool_info := vk.CommandPoolCreateInfo{}
	command_pool_info.sType = .COMMAND_POOL_CREATE_INFO
	command_pool_info.pNext = nil
	command_pool_info.flags = {.RESET_COMMAND_BUFFER}
	command_pool_info.queueFamilyIndex = engine.graphics_queue_family

	for i in 0 ..< FRAME_OVERLAP {
		vk_check(vk.CreateCommandPool(engine.device, &command_pool_info, nil, &engine.frames[i].command_pool))

		// allocate the default command buffer that we will use for rendering
		cmd_alloc_info := vk.CommandBufferAllocateInfo{}
		cmd_alloc_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
		cmd_alloc_info.pNext = nil
		cmd_alloc_info.commandPool = engine.frames[i].command_pool
		cmd_alloc_info.commandBufferCount = 1
		cmd_alloc_info.level = .PRIMARY

		vk_check(vk.AllocateCommandBuffers(engine.device, &cmd_alloc_info, &engine.frames[i].main_command_buffer))
	}

	vk_check(vk.CreateCommandPool(engine.device, &command_pool_info, nil, &engine.imm_command_pool))

	// allocate the command buffer for immediate submits
	cmd_alloc_info := init_command_buffer_allocate_info(engine.imm_command_pool, 1)

	vk_check(vk.AllocateCommandBuffers(engine.device, &cmd_alloc_info, &engine.imm_command_buffer))

	push_deletion_queue(&engine.main_deletion_queue, engine.imm_command_pool)
}

create_image_views :: proc(engine: ^VulkanEngine) {
	engine.swapchain_image_views = make([]vk.ImageView, len(engine.swapchain_images))

	for i in 0 ..< len(engine.swapchain_images) {
		create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = engine.swapchain_images[i],
			viewType = .D2,
			format = engine.swapchain_image_format,
			components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		vk_check(vk.CreateImageView(engine.device, &create_info, nil, &engine.swapchain_image_views[i]))
	}
}

create_swapchain :: proc(engine: ^VulkanEngine) {
	swapchain_support := query_swapchain_support(engine, engine.physical_device)
	defer delete_swapchain_support_details(swapchain_support)

	surface_format, _ := choose_swap_surface_format(swapchain_support.formats)
	present_mode := choose_swap_present_mode(swapchain_support.present_modes)
	extent := choose_swap_extent(engine, &swapchain_support.capabilities)

	image_count := swapchain_support.capabilities.minImageCount + 1

	if swapchain_support.capabilities.maxImageCount > 0 && image_count > swapchain_support.capabilities.maxImageCount {
		image_count = swapchain_support.capabilities.maxImageCount
	}

	create_info: vk.SwapchainCreateInfoKHR
	create_info.sType = .SWAPCHAIN_CREATE_INFO_KHR
	create_info.surface = engine.surface
	create_info.minImageCount = image_count
	create_info.imageFormat = surface_format.format
	create_info.imageColorSpace = surface_format.colorSpace
	create_info.imageExtent = extent
	create_info.imageArrayLayers = 1
	create_info.imageUsage = {.COLOR_ATTACHMENT, .TRANSFER_DST}

	// TODO: Support multiple queues?
	create_info.imageSharingMode = .EXCLUSIVE
	create_info.queueFamilyIndexCount = 0 // Optional
	create_info.pQueueFamilyIndices = nil // Optional

	create_info.preTransform = swapchain_support.capabilities.currentTransform
	create_info.compositeAlpha = {.OPAQUE}
	create_info.presentMode = present_mode
	create_info.clipped = true
	create_info.oldSwapchain = {}

	vk_check(vk.CreateSwapchainKHR(engine.device, &create_info, nil, &engine.swapchain))

	vk.GetSwapchainImagesKHR(engine.device, engine.swapchain, &image_count, nil)
	engine.swapchain_images = make([]vk.Image, image_count)
	vk.GetSwapchainImagesKHR(engine.device, engine.swapchain, &image_count, raw_data(engine.swapchain_images))

	engine.swapchain_image_format = surface_format.format
	engine.swapchain_extent = extent

	draw_image_extent := vk.Extent3D{engine.window_extent.width, engine.window_extent.height, 1}

	engine.draw_image.format = .R16G16B16A16_SFLOAT
	engine.draw_image.extent = draw_image_extent

	draw_image_usages := vk.ImageUsageFlags{.TRANSFER_SRC, .TRANSFER_DST, .STORAGE, .COLOR_ATTACHMENT}

	rimg_info := init_image_create_info(engine.draw_image.format, draw_image_usages, draw_image_extent, ._1)

	rimg_alloc_info := vma.AllocationCreateInfo {
		usage         = .GPU_ONLY,
		requiredFlags = {.DEVICE_LOCAL},
	}

	vma.CreateImage(
		engine.allocator,
		&rimg_info,
		&rimg_alloc_info,
		&engine.draw_image.image,
		&engine.draw_image.allocation,
		nil,
	)

	rview_info := init_imageview_create_info(engine.draw_image.format, engine.draw_image.image, {.COLOR})

	vk_check(vk.CreateImageView(engine.device, &rview_info, nil, &engine.draw_image.image_view))

	push_deletion_queue(&engine.main_deletion_queue, engine.draw_image.image_view)
	push_deletion_queue(&engine.main_deletion_queue, engine.draw_image.image, engine.draw_image.allocation)

	engine.depth_image.format = .D32_SFLOAT
	engine.depth_image.extent = draw_image_extent
	depth_image_usages := vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT}

	dimg_info := init_image_create_info(engine.depth_image.format, depth_image_usages, draw_image_extent, ._1)

	//allocate and create the image
	vma.CreateImage(
		engine.allocator,
		&dimg_info,
		&rimg_alloc_info,
		&engine.depth_image.image,
		&engine.depth_image.allocation,
		nil,
	)

	//build a image-view for the draw image to use for rendering
	dview_info := init_imageview_create_info(engine.depth_image.format, engine.depth_image.image, {.DEPTH})

	vk_check(vk.CreateImageView(engine.device, &dview_info, nil, &engine.depth_image.image_view))

	push_deletion_queue(&engine.main_deletion_queue, engine.depth_image.image_view)
	push_deletion_queue(&engine.main_deletion_queue, engine.depth_image.image, engine.depth_image.allocation)
}

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

init_sync_structures :: proc(engine: ^VulkanEngine) {
	fence_create_info := init_fence_create_info({.SIGNALED})
	semaphore_create_info := init_semaphore_create_info({})

	for &frame in &engine.frames {
		vk_check(vk.CreateFence(engine.device, &fence_create_info, nil, &frame.render_fence))

		vk_check(vk.CreateSemaphore(engine.device, &semaphore_create_info, nil, &frame.swapchain_semaphore))
		vk_check(vk.CreateSemaphore(engine.device, &semaphore_create_info, nil, &frame.render_semaphore))
	}

	vk.CreateFence(engine.device, &fence_create_info, nil, &engine.imm_fence)
	push_deletion_queue(&engine.main_deletion_queue, engine.imm_fence)
}

init_descriptors :: proc(engine: ^VulkanEngine) {
	//create a descriptor pool that will hold 10 sets with 1 image each
	sizes: []PoolSizeRatio = {{.COMBINED_IMAGE_SAMPLER, 1}}

	init_pool(&engine.global_descriptor_allocator, engine.device, 10, sizes, {.UPDATE_AFTER_BIND})
	push_deletion_queue(&engine.main_deletion_queue, engine.global_descriptor_allocator.pool)

	{
		engine.mesh_descriptor_layout = create_descriptor_set_layout(
			engine,
			[?]DescriptorBinding{{0, .COMBINED_IMAGE_SAMPLER}},
			{.VERTEX, .FRAGMENT},
		)
	}

	engine.mesh_descriptors = allocate_pool(
		&engine.global_descriptor_allocator,
		engine.device,
		engine.mesh_descriptor_layout,
	)

	push_deletion_queue(&engine.main_deletion_queue, engine.mesh_descriptor_layout)

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

	vk.CreateSampler(engine.device, &sampler_create_info, nil, &engine.shadow_depth_sampler)

	push_deletion_queue(&engine.main_deletion_queue, engine.shadow_depth_sampler)

	img_info := vk.DescriptorImageInfo{}
	img_info.imageLayout = .DEPTH_READ_ONLY_OPTIMAL
	img_info.imageView = engine.shadow_depth_image.image_view
	img_info.sampler = engine.shadow_depth_sampler

	draw_image_write := vk.WriteDescriptorSet{}
	draw_image_write.sType = .WRITE_DESCRIPTOR_SET
	draw_image_write.pNext = nil

	draw_image_write.dstBinding = 0
	draw_image_write.dstSet = engine.mesh_descriptors
	draw_image_write.descriptorCount = 1
	draw_image_write.descriptorType = .COMBINED_IMAGE_SAMPLER
	draw_image_write.pImageInfo = &img_info

	vk.UpdateDescriptorSets(engine.device, 1, &draw_image_write, 0, nil)
}

init_pipelines :: proc(engine: ^VulkanEngine) {
	init_mesh_pipelines(engine)
}

init_mesh_pipelines :: proc(engine: ^VulkanEngine) {
	triangle_shader, f_ok := util_load_shader_module("shaders/out/shaders.spv", engine.device)

	if !f_ok {
		panic("flip")
	}

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
	engine.mesh_indices_count = u32(len(indices))
	engine.tri_count = u32(len(indices) / 3)

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

init_buffers :: proc(engine: ^VulkanEngine) {
	for &frame in &engine.frames {
		frame.global_uniform_buffer = create_buffer(
			engine,
			size_of(GPUGlobalData),
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)
		device_address_info := vk.BufferDeviceAddressInfo {
			sType  = .BUFFER_DEVICE_ADDRESS_INFO,
			buffer = frame.global_uniform_buffer.buffer,
		}
		frame.global_uniform_address = vk.GetBufferDeviceAddress(engine.device, &device_address_info)

		push_deletion_queue(
			&engine.main_deletion_queue,
			frame.global_uniform_buffer.buffer,
			frame.global_uniform_buffer.allocation,
		)
	}
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

	init_descriptors(engine)
	init_pipelines(engine)

	init_buffers(engine)

	init_imgui(engine)

	return true
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
	start := time.now()
	render_imgui(engine)
	draw(engine)
	engine.frame_time = f32(time.since(start)) / f32(time.Millisecond)
	engine.delta_time = f64(time.since(start)) / f64(time.Second)
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

draw_shadow_map :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) {
	//begin a render pass  connected to our draw image
	depth_attachment := init_depth_attachment_info(engine.shadow_depth_image.image_view, .DEPTH_ATTACHMENT_OPTIMAL)

	render_info := init_rendering_info({1024, 1024}, nil, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	//set dynamic viewport and scissor
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(1024),
		height   = f32(1024),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {x = 0, y = 0},
		extent = {engine.draw_extent.width, engine.draw_extent.height},
	}

	vk.CmdSetScissor(cmd, 0, 1, &scissor)

	vk.CmdBindPipeline(cmd, .GRAPHICS, engine.mesh_shadow_pipeline)

	push_constants: GPUDrawPushConstants
	push_constants.vertex_buffer_address = engine.mesh_buffers.vertex_buffer_address
	push_constants.global_data_buffer_address = current_frame(engine).global_uniform_address

	vk.CmdPushConstants(
		cmd,
		engine.mesh_pipeline_layout,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(GPUDrawPushConstants),
		&push_constants,
	)
	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, engine.mesh_pipeline_layout, 0, 1, &engine.mesh_descriptors, 0, nil)
	vk.CmdBindIndexBuffer(cmd, engine.mesh_buffers.index_buffer.buffer, 0, .UINT32)

	vk.CmdDrawIndexed(cmd, engine.mesh_indices_count, 1, 0, 0, 0)

	vk.CmdEndRendering(cmd)
}

draw_geometry :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) {
	// TODO: Don't create each frame.
	//begin a render pass  connected to our draw image
	color_attachment := init_attachment_info(engine.draw_image.image_view, nil, .GENERAL)
	depth_attachment := init_depth_attachment_info(engine.depth_image.image_view, .DEPTH_ATTACHMENT_OPTIMAL)

	render_info := init_rendering_info(engine.draw_extent, &color_attachment, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	//set dynamic viewport and scissor
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(engine.draw_extent.width),
		height   = f32(engine.draw_extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {x = 0, y = 0},
		extent = {engine.draw_extent.width, engine.draw_extent.height},
	}

	vk.CmdSetScissor(cmd, 0, 1, &scissor)

	vk.CmdBindPipeline(cmd, .GRAPHICS, engine.mesh_pipeline)

	push_constants: GPUDrawPushConstants
	push_constants.vertex_buffer_address = engine.mesh_buffers.vertex_buffer_address
	push_constants.global_data_buffer_address = current_frame(engine).global_uniform_address

	vk.CmdPushConstants(
		cmd,
		engine.mesh_pipeline_layout,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(GPUDrawPushConstants),
		&push_constants,
	)
	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, engine.mesh_pipeline_layout, 0, 1, &engine.mesh_descriptors, 0, nil)
	vk.CmdBindIndexBuffer(cmd, engine.mesh_buffers.index_buffer.buffer, 0, .UINT32)

	vk.CmdDrawIndexed(cmd, engine.mesh_indices_count, 1, 0, 0, 0)

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

	camera := get_entity(game_state.camera_id)

	// Camera matrices
	{
		aspect_ratio := f32(engine.window_extent.width) / f32(engine.window_extent.height)

		translation := linalg.matrix4_translate(camera != nil ? camera.translation : {})
		rotation := linalg.matrix4_from_quaternion(camera != nil ? camera.rotation : {})

		view_matrix := linalg.inverse(linalg.mul(translation, rotation))

		// view_matrix := linalg.matrix4_look_at_f32(game_state.camera_pos, {0, 0, 0}, {0, 1, 0})

		projection_matrix := linalg.matrix4_infinite_perspective_z0_f32(
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
			game_state.environment.sun_pos,
			game_state.environment.sun_target,
			{0.0, 1.0, 0.0},
		)
		sun_projection_matrix := linalg.matrix_ortho3d_z0_f32(-10, 10, -10, 10, 0.1, 100.0)
		sun_projection_matrix[1][1] *= -1.0

		global_uniform_data.sun_view_projection_matrix = sun_projection_matrix * sun_view_matrix

		global_uniform_data.view_projection_i_matrix = linalg.matrix4_inverse(
			global_uniform_data.view_projection_matrix,
		)
	}

	global_uniform_data.sun_color = game_state.environment.sun_color
	global_uniform_data.sky_color = game_state.environment.sky_color
	global_uniform_data.bias = game_state.environment.bias

	global_uniform_data.camera_pos = hlsl.float3(camera != nil ? camera.translation : [3]f32{0, 0, 0})
	global_uniform_data.sun_pos = hlsl.float3(game_state.environment.sun_pos)

	write_buffer(&current_frame(engine).global_uniform_buffer, &global_uniform_data)
}

draw :: proc(engine: ^VulkanEngine) {
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

	swapchain_image_index: u32

	vk_check(
		vk.AcquireNextImageKHR(
			engine.device,
			engine.swapchain,
			1_000_000_000,
			current_frame(engine).swapchain_semaphore,
			vk.Fence(0), // null
			&swapchain_image_index,
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
	util_transition_image(cmd, engine.draw_image.image, .UNDEFINED, .GENERAL)

	draw_background(engine, cmd)

	// Begin shadow pass
	util_transition_image(cmd, engine.shadow_depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	draw_shadow_map(engine, cmd)

	util_transition_image(cmd, engine.draw_image.image, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL)
	util_transition_image(cmd, engine.depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	util_transition_image(cmd, engine.shadow_depth_image.image, .DEPTH_ATTACHMENT_OPTIMAL, .DEPTH_READ_ONLY_OPTIMAL)

	draw_geometry(engine, cmd)

	util_transition_image(cmd, engine.draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
	util_transition_image(cmd, engine.swapchain_images[swapchain_image_index], .UNDEFINED, .TRANSFER_DST_OPTIMAL)

	// execute a copy from the draw image into the swapchain
	util_copy_image_to_image(
		cmd,
		engine.draw_image.image,
		engine.swapchain_images[swapchain_image_index],
		engine.draw_extent,
		engine.swapchain_extent,
	)

	// set swapchain image layout to Attachment Optimal so we can draw it
	util_transition_image(
		cmd,
		engine.swapchain_images[swapchain_image_index],
		.TRANSFER_DST_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
	)

	//draw imgui into the swapchain image
	draw_imgui(engine, cmd, engine.swapchain_image_views[swapchain_image_index])

	// set swapchain image layout to Present so we can show it on the screen
	util_transition_image(
		cmd,
		engine.swapchain_images[swapchain_image_index],
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
	)

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
		pImageIndices      = &swapchain_image_index,
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
