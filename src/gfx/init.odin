package gfx

import "base:runtime"

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strings"

import glfw "vendor:glfw"
import vk "vendor:vulkan"

import vma "deps:odin-vma"

fetch_queues :: proc(device: vk.PhysicalDevice) -> bool {
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, raw_data(queue_families))

	has_graphics := false

	for queue_family, i in &queue_families {
		if .GRAPHICS in queue_family.queueFlags {
			r_ctx.graphics_queue_family = u32(i)
			has_graphics = true
		}
	}

	return has_graphics
}

// This allocates format and present_mode slices.
query_swapchain_support :: proc(device: vk.PhysicalDevice) -> SwapChainSupportDetails {
	details: SwapChainSupportDetails

	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, r_ctx.surface, &details.capabilities)

	{
		format_count: u32
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, r_ctx.surface, &format_count, nil)

		formats := make([]vk.SurfaceFormatKHR, format_count)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, r_ctx.surface, &format_count, raw_data(formats))

		details.formats = formats
	}

	{
		present_mode_count: u32
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, r_ctx.surface, &present_mode_count, nil)

		present_modes := make([]vk.PresentModeKHR, present_mode_count)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, r_ctx.surface, &present_mode_count, raw_data(present_modes))

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

choose_swap_extent :: proc(capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
	if (capabilities.currentExtent.width != max(u32)) {
		return capabilities.currentExtent
	} else {
		width, height := glfw.GetFramebufferSize(r_ctx.window)

		actual_extent := vk.Extent2D{u32(width), u32(height)}

		actual_extent.width = clamp(actual_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width)
		actual_extent.height = clamp(actual_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)

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

is_device_suitable :: proc(device: vk.PhysicalDevice) -> bool {
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
		swapchain_support := query_swapchain_support(device)
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

		for &available in &available_extensions {
			if libc.strcmp(cstring(&available.extensionName[0]), expected_extension) == 0 {
				found = true
				break
			}
		}

		found or_return
	}

	return true
}

create_surface :: proc() {
	vk_check(glfw.CreateWindowSurface(r_ctx.instance, r_ctx.window, nil, &r_ctx.surface))
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

setup_debug_messenger :: proc() {
	if ENABLE_VALIDATION_LAYERS {
		fmt.println("Creating Debug Messenger")
		create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE, .WARNING, .INFO, .ERROR},
			messageType     = {.GENERAL, .VALIDATION},
			pfnUserCallback = debug_callback,
			pUserData       = nil,
		}

		vk_check(vk.CreateDebugUtilsMessengerEXT(r_ctx.instance, &create_info, nil, &r_ctx.debug_messenger))
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

		for &layer_property in &available_layers {
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

create_instance :: proc() -> bool {
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

	vk_check(vk.CreateInstance(&create_info, nil, &r_ctx.instance))

	// Load instance-specific procedures
	vk.load_proc_addresses_instance(r_ctx.instance)

	n_ext: u32
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, nil)

	extension_props := make([]vk.ExtensionProperties, n_ext)
	defer delete(extension_props)

	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, raw_data(extension_props))

	fmt.println("Available Extensions:")

	bytes, ok := os.read_entire_file("")

	for &ext in &extension_props {
		fmt.printfln(" - %s", cstring(&ext.extensionName[0]))
	}

	if ENABLE_VALIDATION_LAYERS && !check_validation_layers() {
		panic("Validation layers are not available")
	}

	return true
}

pick_physical_device :: proc() {
	device_count: u32 = 0

	vk.EnumeratePhysicalDevices(r_ctx.instance, &device_count, nil)

	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(r_ctx.instance, &device_count, raw_data(devices))

	for device in devices {
		if is_device_suitable(device) {
			r_ctx.physical_device = device
			break
		}
	}

	if r_ctx.physical_device == nil {
		panic("No GPU found that supports all required features.")
	}
}

create_logical_device :: proc() {
	queue_priority: f32 = 1.0

	queue_create_info: vk.DeviceQueueCreateInfo
	queue_create_info.sType = .DEVICE_QUEUE_CREATE_INFO
	queue_create_info.queueFamilyIndex = r_ctx.graphics_queue_family
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

	vk_check(vk.CreateDevice(r_ctx.physical_device, &device_create_info, nil, &r_ctx.device))

	assert(r_ctx.device != nil)

	vk.GetDeviceQueue(r_ctx.device, r_ctx.graphics_queue_family, 0, &r_ctx.graphics_queue)
}

init_commands :: proc() {
	command_pool_info := vk.CommandPoolCreateInfo{}
	command_pool_info.sType = .COMMAND_POOL_CREATE_INFO
	command_pool_info.pNext = nil
	command_pool_info.flags = {.RESET_COMMAND_BUFFER}
	command_pool_info.queueFamilyIndex = r_ctx.graphics_queue_family

	for i in 0 ..< FRAME_OVERLAP {
		vk_check(vk.CreateCommandPool(r_ctx.device, &command_pool_info, nil, &r_ctx.frames[i].command_pool))

		// allocate the default command buffer that we will use for rendering
		cmd_alloc_info := vk.CommandBufferAllocateInfo{}
		cmd_alloc_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
		cmd_alloc_info.pNext = nil
		cmd_alloc_info.commandPool = r_ctx.frames[i].command_pool
		cmd_alloc_info.commandBufferCount = 1
		cmd_alloc_info.level = .PRIMARY

		vk_check(vk.AllocateCommandBuffers(r_ctx.device, &cmd_alloc_info, &r_ctx.frames[i].main_command_buffer))
	}

	vk_check(vk.CreateCommandPool(r_ctx.device, &command_pool_info, nil, &r_ctx.imm_command_pool))

	// allocate the command buffer for immediate submits
	cmd_alloc_info := init_command_buffer_allocate_info(r_ctx.imm_command_pool, 1)

	vk_check(vk.AllocateCommandBuffers(r_ctx.device, &cmd_alloc_info, &r_ctx.imm_command_buffer))

	push_deletion_queue(&r_ctx.main_deletion_queue, r_ctx.imm_command_pool)
}

create_swapchain :: proc() {
	swapchain_support := query_swapchain_support(r_ctx.physical_device)
	defer delete_swapchain_support_details(swapchain_support)

	surface_format, _ := choose_swap_surface_format(swapchain_support.formats)
	present_mode := choose_swap_present_mode(swapchain_support.present_modes)
	extent := choose_swap_extent(&swapchain_support.capabilities)

	image_count := swapchain_support.capabilities.minImageCount + 1

	if swapchain_support.capabilities.maxImageCount > 0 && image_count > swapchain_support.capabilities.maxImageCount {
		image_count = swapchain_support.capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType                 = .SWAPCHAIN_CREATE_INFO_KHR,
		surface               = r_ctx.surface,
		minImageCount         = image_count,
		imageFormat           = surface_format.format,
		imageColorSpace       = surface_format.colorSpace,
		imageExtent           = extent,
		imageArrayLayers      = 1,
		imageUsage            = {.COLOR_ATTACHMENT, .TRANSFER_DST},

		// TODO: Support multiple queues?
		imageSharingMode      = .EXCLUSIVE,
		queueFamilyIndexCount = 0, // Optional
		pQueueFamilyIndices   = nil, // Optional
		preTransform          = swapchain_support.capabilities.currentTransform,
		compositeAlpha        = {.OPAQUE},
		presentMode           = present_mode,
		clipped               = true,
		oldSwapchain          = {},
	}

	vk_check(vk.CreateSwapchainKHR(r_ctx.device, &create_info, nil, &r_ctx.swapchain))

	vk.GetSwapchainImagesKHR(r_ctx.device, r_ctx.swapchain, &image_count, nil)
	r_ctx.swapchain_images = make([]vk.Image, image_count)
	vk.GetSwapchainImagesKHR(r_ctx.device, r_ctx.swapchain, &image_count, raw_data(r_ctx.swapchain_images))

	r_ctx.swapchain_image_format = surface_format.format
	r_ctx.swapchain_extent = extent

	r_ctx.swapchain_image_views = make([]vk.ImageView, len(r_ctx.swapchain_images))

	for i in 0 ..< len(r_ctx.swapchain_images) {
		create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = r_ctx.swapchain_images[i],
			viewType = .D2,
			format = r_ctx.swapchain_image_format,
			components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
			subresourceRange = {aspectMask = {.COLOR}, baseMipLevel = 0, levelCount = 1, baseArrayLayer = 0, layerCount = 1},
		}

		vk_check(vk.CreateImageView(r_ctx.device, &create_info, nil, &r_ctx.swapchain_image_views[i]))
	}
}

create_draw_images :: proc(msaa_samples: vk.SampleCountFlag) {
	r_ctx.msaa_samples = msaa_samples

	draw_image_format : vk.Format = .R16G16B16A16_SFLOAT
	draw_image_extent := vk.Extent3D{r_ctx.window_extent.width, r_ctx.window_extent.height, 1}
	draw_image_usages := vk.ImageUsageFlags{.TRANSFER_SRC, .TRANSFER_DST, .STORAGE, .COLOR_ATTACHMENT}

	r_ctx.draw_image = create_image(draw_image_format, draw_image_extent, draw_image_usages, msaa_samples)
	create_image_view(&r_ctx.draw_image, {.COLOR})

	// Used for MSAA resolution
	r_ctx.resolve_image = create_image(draw_image_format, draw_image_extent, draw_image_usages, ._1)
	create_image_view(&r_ctx.resolve_image, {.COLOR})

	r_ctx.depth_image = create_image(.D32_SFLOAT, draw_image_extent, {.DEPTH_STENCIL_ATTACHMENT}, msaa_samples)
	create_image_view(&r_ctx.depth_image, {.DEPTH})

	push_deletion_queue(&r_ctx.main_deletion_queue, r_ctx.depth_image.image_view)
	push_deletion_queue(&r_ctx.main_deletion_queue, r_ctx.depth_image.image, r_ctx.depth_image.allocation)

	push_deletion_queue(&r_ctx.main_deletion_queue, r_ctx.resolve_image.image_view)
	push_deletion_queue(&r_ctx.main_deletion_queue, r_ctx.resolve_image.image, r_ctx.resolve_image.allocation)

	push_deletion_queue(&r_ctx.main_deletion_queue, r_ctx.draw_image.image_view)
	push_deletion_queue(&r_ctx.main_deletion_queue, r_ctx.draw_image.image, r_ctx.draw_image.allocation)
}


init_sync_structures :: proc() {
	fence_create_info := init_fence_create_info({.SIGNALED})
	semaphore_create_info := init_semaphore_create_info({})

	for &frame in &r_ctx.frames {
		vk_check(vk.CreateFence(r_ctx.device, &fence_create_info, nil, &frame.render_fence))

		vk_check(vk.CreateSemaphore(r_ctx.device, &semaphore_create_info, nil, &frame.swapchain_semaphore))
		vk_check(vk.CreateSemaphore(r_ctx.device, &semaphore_create_info, nil, &frame.render_semaphore))
	}

	vk.CreateFence(r_ctx.device, &fence_create_info, nil, &r_ctx.imm_fence)
	push_deletion_queue(&r_ctx.main_deletion_queue, r_ctx.imm_fence)
}
