package vma

STATS_STRING_ENABLED :: 1
VULKAN_VERSION :: 1002000
DEDICATED_ALLOCATION :: 1
BIND_MEMORY2 :: 1
MEMORY_BUDGET :: 1
BUFFER_DEVICE_ADDRESS :: 1
MEMORY_PRIORITY :: 1
EXTERNAL_MEMORY :: 1

Handle :: distinct rawptr
NonDispatchableHandle :: distinct u64

Pool :: distinct Handle
Allocation :: distinct Handle
Allocator :: distinct Handle
DefragmentationContext :: distinct Handle

VirtualAllocation :: distinct Handle

VirtualBlock :: distinct Handle
