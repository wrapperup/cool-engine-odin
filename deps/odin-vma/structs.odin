package vma

import vk "vendor:vulkan"

DeviceMemoryCallbacks :: struct {
	pfnAllocate: PFN_vmaAllocateDeviceMemoryFunction,
	pfnFree:     PFN_vmaFreeDeviceMemoryFunction,
	pUserData:   rawptr,
}

VulkanFunctions :: struct {
	unused_1:                              proc(), //vkGetInstanceProcAddr
	unused_2:                              proc(), //vkGetDeviceProcAddr
	GetPhysicalDeviceProperties:           vk.ProcGetPhysicalDeviceProperties,
	GetPhysicalDeviceMemoryProperties:     vk.ProcGetPhysicalDeviceMemoryProperties,
	AllocateMemory:                        vk.ProcAllocateMemory,
	FreeMemory:                            vk.ProcFreeMemory,
	MapMemory:                             vk.ProcMapMemory,
	UnmapMemory:                           vk.ProcUnmapMemory,
	FlushMappedMemoryRanges:               vk.ProcFlushMappedMemoryRanges,
	InvalidateMappedMemoryRanges:          vk.ProcInvalidateMappedMemoryRanges,
	BindBufferMemory:                      vk.ProcBindBufferMemory,
	BindImageMemory:                       vk.ProcBindImageMemory,
	GetBufferMemoryRequirements:           vk.ProcGetBufferMemoryRequirements,
	GetImageMemoryRequirements:            vk.ProcGetImageMemoryRequirements,
	CreateBuffer:                          vk.ProcCreateBuffer,
	DestroyBuffer:                         vk.ProcDestroyBuffer,
	CreateImage:                           vk.ProcCreateImage,
	DestroyImage:                          vk.ProcDestroyImage,
	CmdCopyBuffer:                         vk.ProcCmdCopyBuffer,
	GetBufferMemoryRequirements2KHR:       vk.ProcGetBufferMemoryRequirements2KHR,
	GetImageMemoryRequirements2KHR:        vk.ProcGetImageMemoryRequirements2KHR,
	BindBufferMemory2KHR:                  vk.ProcBindBufferMemory2KHR,
	BindImageMemory2KHR:                   vk.ProcBindImageMemory2KHR,
	GetPhysicalDeviceMemoryProperties2KHR: vk.ProcGetPhysicalDeviceMemoryProperties2KHR,
}

AllocatorCreateInfo :: struct {
	flags:                          AllocatorCreateFlags,
	physicalDevice:                 vk.PhysicalDevice,
	device:                         vk.Device,
	preferredLargeHeapBlockSize:    vk.DeviceSize,
	pAllocationCallbacks:           ^vk.AllocationCallbacks,
	pDeviceMemoryCallbacks:         ^DeviceMemoryCallbacks,
	pHeapSizeLimit:                 ^vk.DeviceSize,
	pVulkanFunctions:               ^VulkanFunctions,
	instance:                       vk.Instance,
	vulkanApiVersion:               u32,
	pTypeExternalMemoryHandleTypes: ^vk.ExternalMemoryHandleTypeFlagsKHR,
}

AllocatorInfo :: struct {
	instance:       vk.Instance,
	physicalDevice: vk.PhysicalDevice,
	device:         vk.Device,
}

Statistics :: struct {
	blockCount:      u32,
	allocationCount: u32,
	blockBytes:      vk.DeviceSize,
	allocationBytes: vk.DeviceSize,
}

DetailedStatistics :: struct {
	statistics:         Statistics,
	unusedRangeCount:   u32,
	allocationSizeMin:  vk.DeviceSize,
	allocationSizeMax:  vk.DeviceSize,
	unusedRangeSizeMin: vk.DeviceSize,
	unusedRangeSizeMax: vk.DeviceSize,
}

TotalStatistics :: struct {
	memoryType: [32]DetailedStatistics,
	memoryHeap: [16]DetailedStatistics,
	total:      DetailedStatistics,
}

Budget :: struct {
	statistics: Statistics,
	usage:      vk.DeviceSize,
	budget:     vk.DeviceSize,
}

AllocationCreateInfo :: struct {
	flags:          AllocationCreateFlags,
	usage:          MemoryUsage,
	requiredFlags:  vk.MemoryPropertyFlags,
	preferredFlags: vk.MemoryPropertyFlags,
	memoryTypeBits: u32,
	pool:           Pool,
	pUserData:      rawptr,
	priority:       f32,
}

PoolCreateInfo :: struct {
	memoryTypeIndex:        u32,
	flags:                  PoolCreateFlags,
	blockSize:              vk.DeviceSize,
	minBlockCount:          uint,
	maxBlockCount:          uint,
	priority:               f32,
	minAllocationAlignment: vk.DeviceSize,
	pMemoryAllocateNext:    rawptr,
}

AllocationInfo :: struct {
	memoryType:   u32,
	deviceMemory: vk.DeviceMemory,
	offset:       vk.DeviceSize,
	size:         vk.DeviceSize,
	pMappedData:  rawptr,
	pUserData:    rawptr,
	pName:        cstring,
}

DefragmentationInfo :: struct {
	flags:                 DefragmentationFlags,
	pool:                  Pool,
	maxBytesPerPass:       vk.DeviceSize,
	maxAllocationsPerPass: u32,
}

DefragmentationMove :: struct {
	operation:        DefragmentationMoveOperation,
	srcAllocation:    Allocation,
	dstTmpAllocation: Allocation,
}

DefragmentationPassMoveInfo :: struct {
	moveCount: u32,
	pMoves:    ^DefragmentationMove,
}

DefragmentationStats :: struct {
	bytesMoved:              vk.DeviceSize,
	bytesFreed:              vk.DeviceSize,
	allocationsMoved:        u32,
	deviceMemoryBlocksFreed: u32,
}

VirtualBlockCreateInfo :: struct {
	size:                 vk.DeviceSize,
	flags:                VirtualBlockCreateFlags,
	pAllocationCallbacks: ^vk.AllocationCallbacks,
}

VirtualAllocationCreateInfo :: struct {
	size:      vk.DeviceSize,
	alignment: vk.DeviceSize,
	flags:     VirtualAllocationCreateFlags,
	pUserData: rawptr,
}

VirtualAllocationInfo :: struct {
	offset:    vk.DeviceSize,
	size:      vk.DeviceSize,
	pUserData: rawptr,
}