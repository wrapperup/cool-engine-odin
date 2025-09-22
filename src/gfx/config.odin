package gfx

import vk "vendor:vulkan"

// Set required features to enable here. These are used to pick the physical device as well.
REQUIRED_FEATURES := vk.PhysicalDeviceFeatures2 {
	sType = .PHYSICAL_DEVICE_FEATURES_2,
	features = {
		samplerAnisotropy = true,
		shaderStorageImageMultisample = true,
		shaderImageGatherExtended = true,
		multiDrawIndirect = true,
		geometryShader = true,
		shaderInt64 = true,
		shaderInt16 = true,
		shaderFloat64 = true,
	},
	pNext = &REQUIRED_VK_11_FEATURES,
}

REQUIRED_VK_11_FEATURES := vk.PhysicalDeviceVulkan11Features {
	sType                         = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
	pNext                         = &REQUIRED_VK_12_FEATURES,
	variablePointers              = true,
	variablePointersStorageBuffer = true,
	shaderDrawParameters          = true,
}

REQUIRED_VK_12_FEATURES := vk.PhysicalDeviceVulkan12Features {
	sType                  = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
	pNext                  = &REQUIRED_VK_13_FEATURES,
	bufferDeviceAddress    = true,
	descriptorIndexing     = true,
	storagePushConstant8   = true,
	shaderInt8             = true,
	runtimeDescriptorArray = true,
	scalarBlockLayout      = true,
}

REQUIRED_VK_13_FEATURES := vk.PhysicalDeviceVulkan13Features {
	sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
	dynamicRendering = true,
	synchronization2 = true,
}

// Set required extensions to support.
DEVICE_EXTENSIONS := []cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.KHR_DYNAMIC_RENDERING_EXTENSION_NAME, // Enabled by default in 1.3
	vk.KHR_SHADER_NON_SEMANTIC_INFO_EXTENSION_NAME, // Enable by default in 1.3
}

// Set validation layers to enable.
VALIDATION_LAYERS := []cstring{"VK_LAYER_KHRONOS_validation"}

// Set validation features to enable.
VALIDATION_FEATURES := []vk.ValidationFeatureEnableEXT{.DEBUG_PRINTF}

// Number of frames to provide in flight.
FRAME_OVERLAP :: 2
