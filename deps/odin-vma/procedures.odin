package vma

import c "core:c"
import vk "vendor:vulkan"

PFN_vmaAllocateDeviceMemoryFunction :: proc "c" (
	allocator: Allocator,
	memoryType: u32,
	memory: vk.DeviceMemory,
	size: vk.DeviceSize,
	pUserData: rawptr,
)
PFN_vmaFreeDeviceMemoryFunction :: proc "c" (
	allocator: Allocator,
	memoryType: u32,
	memory: vk.DeviceMemory,
	size: vk.DeviceSize,
	pUserData: rawptr,
)

foreign import VulkanMemoryAllocator "external/VulkanMemoryAllocator.lib"

create_vulkan_functions :: proc() -> VulkanFunctions {
	return(
		{
			AllocateMemory = vk.AllocateMemory,
			BindBufferMemory = vk.BindBufferMemory,
			BindBufferMemory2KHR = vk.BindBufferMemory2,
			BindImageMemory = vk.BindImageMemory,
			BindImageMemory2KHR = vk.BindImageMemory2,
			CmdCopyBuffer = vk.CmdCopyBuffer,
			CreateBuffer = vk.CreateBuffer,
			CreateImage = vk.CreateImage,
			DestroyBuffer = vk.DestroyBuffer,
			DestroyImage = vk.DestroyImage,
			FlushMappedMemoryRanges = vk.FlushMappedMemoryRanges,
			FreeMemory = vk.FreeMemory,
			GetBufferMemoryRequirements = vk.GetBufferMemoryRequirements,
			GetBufferMemoryRequirements2KHR = vk.GetBufferMemoryRequirements2,
			GetImageMemoryRequirements = vk.GetImageMemoryRequirements,
			GetImageMemoryRequirements2KHR = vk.GetImageMemoryRequirements2,
			GetPhysicalDeviceMemoryProperties = vk.GetPhysicalDeviceMemoryProperties,
			GetPhysicalDeviceMemoryProperties2KHR = vk.GetPhysicalDeviceMemoryProperties2,
			GetPhysicalDeviceProperties = vk.GetPhysicalDeviceProperties,
			InvalidateMappedMemoryRanges = vk.InvalidateMappedMemoryRanges,
			MapMemory = vk.MapMemory,
			UnmapMemory = vk.UnmapMemory,
		} \
	)
}

@(default_calling_convention = "c", link_prefix = "vma")
foreign VulkanMemoryAllocator {
	CreateAllocator :: proc(pCreateInfo: ^AllocatorCreateInfo, pAllocator: ^Allocator) -> vk.Result ---
	DestroyAllocator :: proc(allocator: Allocator) ---
	GetAllocatorInfo :: proc(allocator: Allocator, pAllocatorInfo: ^AllocatorInfo) ---
	GetPhysicalDeviceProperties :: proc(allocator: Allocator, ppPhysicalDeviceProperties: ^^vk.PhysicalDeviceProperties) ---
	GetMemoryProperties :: proc(allocator: Allocator, ppPhysicalDeviceMemoryProperties: ^^vk.PhysicalDeviceMemoryProperties) ---
	GetMemoryTypeProperties :: proc(allocator: Allocator, memoryTypeIndex: u32, pFlags: ^vk.MemoryPropertyFlags) ---
	SetCurrentFrameIndex :: proc(allocator: Allocator, frameIndex: u32) ---
	CalculateStatistics :: proc(allocator: Allocator, pStats: ^TotalStatistics) ---
	GetHeapBudgets :: proc(allocator: Allocator, pBudgets: ^Budget) ---
	FindMemoryTypeIndex :: proc(allocator: Allocator, memoryTypeBits: u32, pAllocationCreateInfo: ^AllocationCreateInfo, pMemoryTypeIndex: ^u32) -> vk.Result ---
	FindMemoryTypeIndexForBufferInfo :: proc(allocator: Allocator, pBufferCreateInfo: ^vk.BufferCreateInfo, pAllocationCreateInfo: ^AllocationCreateInfo, pMemoryTypeIndex: ^u32) -> vk.Result ---
	FindMemoryTypeIndexForImageInfo :: proc(allocator: Allocator, pImageCreateInfo: ^vk.ImageCreateInfo, pAllocationCreateInfo: ^AllocationCreateInfo, pMemoryTypeIndex: ^u32) -> vk.Result ---
	CreatePool :: proc(allocator: Allocator, pCreateInfo: ^PoolCreateInfo, pPool: ^Pool) -> vk.Result ---
	DestroyPool :: proc(allocator: Allocator, pool: Pool) ---
	GetPoolStatistics :: proc(allocator: Allocator, pool: Pool, pPoolStats: ^Statistics) ---
	CalculatePoolStatistics :: proc(allocator: Allocator, pool: Pool, pPoolStats: ^DetailedStatistics) ---
	CheckPoolCorruption :: proc(allocator: Allocator, pool: Pool) -> vk.Result ---
	GetPoolName :: proc(allocator: Allocator, pool: Pool, ppName: ^cstring) ---
	SetPoolName :: proc(allocator: Allocator, pool: Pool, pName: cstring) ---
	AllocateMemory :: proc(allocator: Allocator, pVkMemoryRequirements: ^vk.MemoryRequirements, pCreateInfo: ^AllocationCreateInfo, pAllocation: ^Allocation, pAllocationInfo: ^AllocationInfo) -> vk.Result ---
	AllocateMemoryPages :: proc(allocator: Allocator, pVkMemoryRequirements: ^vk.MemoryRequirements, pCreateInfo: ^AllocationCreateInfo, allocationCount: uint, pAllocations: ^Allocation, pAllocationInfo: ^AllocationInfo) -> vk.Result ---
	AllocateMemoryForBuffer :: proc(allocator: Allocator, buffer: vk.Buffer, pCreateInfo: ^AllocationCreateInfo, pAllocation: ^Allocation, pAllocationInfo: ^AllocationInfo) -> vk.Result ---
	AllocateMemoryForImage :: proc(allocator: Allocator, image: vk.Image, pCreateInfo: ^AllocationCreateInfo, pAllocation: ^Allocation, pAllocationInfo: ^AllocationInfo) -> vk.Result ---
	FreeMemory :: proc(allocator: Allocator, allocation: Allocation) ---
	FreeMemoryPages :: proc(allocator: Allocator, allocationCount: uint, pAllocations: ^Allocation) ---
	GetAllocationInfo :: proc(allocator: Allocator, allocation: Allocation, pAllocationInfo: ^AllocationInfo) ---
	SetAllocationUserData :: proc(allocator: Allocator, allocation: Allocation, pUserData: rawptr) ---
	SetAllocationName :: proc(allocator: Allocator, allocation: Allocation, pName: cstring) ---
	GetAllocationMemoryProperties :: proc(allocator: Allocator, allocation: Allocation, pFlags: ^vk.MemoryPropertyFlags) ---
	MapMemory :: proc(allocator: Allocator, allocation: Allocation, ppData: ^rawptr) -> vk.Result ---
	UnmapMemory :: proc(allocator: Allocator, allocation: Allocation) ---
	FlushAllocation :: proc(allocator: Allocator, allocation: Allocation, offset: vk.DeviceSize, size: vk.DeviceSize) -> vk.Result ---
	InvalidateAllocation :: proc(allocator: Allocator, allocation: Allocation, offset: vk.DeviceSize, size: vk.DeviceSize) -> vk.Result ---
	FlushAllocations :: proc(allocator: Allocator, allocationCount: u32, allocations: ^Allocation, offsets: ^vk.DeviceSize, sizes: ^vk.DeviceSize) -> vk.Result ---
	InvalidateAllocations :: proc(allocator: Allocator, allocationCount: u32, allocations: ^Allocation, offsets: ^vk.DeviceSize, sizes: ^vk.DeviceSize) -> vk.Result ---
	CheckCorruption :: proc(allocator: Allocator, memoryTypeBits: u32) -> vk.Result ---
	BeginDefragmentation :: proc(allocator: Allocator, pInfo: ^DefragmentationInfo, pContext: ^DefragmentationContext) -> vk.Result ---
	EndDefragmentation :: proc(allocator: Allocator, context_: DefragmentationContext, pStats: ^DefragmentationStats) ---
	BeginDefragmentationPass :: proc(allocator: Allocator, context_: DefragmentationContext, pPassInfo: ^DefragmentationPassMoveInfo) -> vk.Result ---
	EndDefragmentationPass :: proc(allocator: Allocator, context_: DefragmentationContext, pPassInfo: ^DefragmentationPassMoveInfo) -> vk.Result ---
	BindBufferMemory :: proc(allocator: Allocator, allocation: Allocation, buffer: vk.Buffer) -> vk.Result ---
	BindBufferMemory2 :: proc(allocator: Allocator, allocation: Allocation, allocationLocalOffset: vk.DeviceSize, buffer: vk.Buffer, pNext: rawptr) -> vk.Result ---
	BindImageMemory :: proc(allocator: Allocator, allocation: Allocation, image: vk.Image) -> vk.Result ---
	BindImageMemory2 :: proc(allocator: Allocator, allocation: Allocation, allocationLocalOffset: vk.DeviceSize, image: vk.Image, pNext: rawptr) -> vk.Result ---
	CreateBuffer :: proc(allocator: Allocator, pBufferCreateInfo: ^vk.BufferCreateInfo, pAllocationCreateInfo: ^AllocationCreateInfo, pBuffer: ^vk.Buffer, pAllocation: ^Allocation, pAllocationInfo: ^AllocationInfo) -> vk.Result ---
	CreateBufferWithAlignment :: proc(allocator: Allocator, pBufferCreateInfo: ^vk.BufferCreateInfo, pAllocationCreateInfo: ^AllocationCreateInfo, minAlignment: vk.DeviceSize, pBuffer: ^vk.Buffer, pAllocation: ^Allocation, pAllocationInfo: ^AllocationInfo) -> vk.Result ---
	CreateAliasingBuffer :: proc(allocator: Allocator, allocation: Allocation, pBufferCreateInfo: ^vk.BufferCreateInfo, pBuffer: ^vk.Buffer) -> vk.Result ---
	DestroyBuffer :: proc(allocator: Allocator, buffer: vk.Buffer, allocation: Allocation) ---
	CreateImage :: proc(allocator: Allocator, pImageCreateInfo: ^vk.ImageCreateInfo, pAllocationCreateInfo: ^AllocationCreateInfo, pImage: ^vk.Image, pAllocation: ^Allocation, pAllocationInfo: ^AllocationInfo) -> vk.Result ---
	CreateAliasingImage :: proc(allocator: Allocator, allocation: Allocation, pImageCreateInfo: ^vk.ImageCreateInfo, pImage: ^vk.Image) -> vk.Result ---
	DestroyImage :: proc(allocator: Allocator, image: vk.Image, allocation: Allocation) ---
	CreateVirtualBlock :: proc(pCreateInfo: ^VirtualBlockCreateInfo, pVirtualBlock: ^VirtualBlock) -> vk.Result ---
	DestroyVirtualBlock :: proc(virtualBlock: VirtualBlock) ---
	IsVirtualBlockEmpty :: proc(virtualBlock: VirtualBlock) -> c.bool ---
	GetVirtualAllocationInfo :: proc(virtualBlock: VirtualBlock, allocation: VirtualAllocation, pVirtualAllocInfo: ^VirtualAllocationInfo) ---
	VirtualAllocate :: proc(virtualBlock: VirtualBlock, pCreateInfo: ^VirtualAllocationCreateInfo, pAllocation: ^VirtualAllocation, pOffset: ^vk.DeviceSize) -> vk.Result ---
	VirtualFree :: proc(virtualBlock: VirtualBlock, allocation: VirtualAllocation) ---
	ClearVirtualBlock :: proc(virtualBlock: VirtualBlock) ---
	SetVirtualAllocationUserData :: proc(virtualBlock: VirtualBlock, allocation: VirtualAllocation, pUserData: rawptr) ---
	GetVirtualBlockStatistics :: proc(virtualBlock: VirtualBlock, pStats: ^Statistics) ---
	CalculateVirtualBlockStatistics :: proc(virtualBlock: VirtualBlock, pStats: ^DetailedStatistics) ---
	BuildVirtualBlockStatsString :: proc(virtualBlock: VirtualBlock, ppStatsString: ^cstring, detailedMap:  c.bool) ---
	FreeVirtualBlockStatsString :: proc(virtualBlock: VirtualBlock, pStatsString: cstring) ---
	BuildStatsString :: proc(allocator: Allocator, ppStatsString: ^cstring, detailedMap:  c.bool) ---
	FreeStatsString :: proc(allocator: Allocator, pStatsString: cstring) ---
}
