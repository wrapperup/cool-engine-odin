### odin-vma

Binding for VulkanMemoryAllocator.

## Usage

```
vulkan_functions := vma.create_vulkan_functions();

create_info := vma.AllocatorCreateInfo {
	vulkanApiVersion = vulkan.API_VERSION_1_2,
	physicalDevice = physical_device,
	device = device,
	instance = instance,
	pVulkanFunctions = &vulkan_functions,
};

if vma.CreateAllocator(&create_info, &allocator) != .SUCCESS {
	log.error("Failed to CreateAllocator");
}

```

## Introduction to vma
https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/quick_start.html#quick_start_initialization

## Building vma
Build the library with dynamically linked and statically linked off - we are passing the pointers to vma manually.

```
option(VMA_STATIC_VULKAN_FUNCTIONS "Link statically with Vulkan API" OFF)
option(VMA_DYNAMIC_VULKAN_FUNCTIONS "Fetch pointers to Vulkan functions internally (no static linking)" OFF)
```
