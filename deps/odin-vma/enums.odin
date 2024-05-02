package vma

import c "core:c"

AllocatorCreateFlags :: distinct bit_set[AllocatorCreateFlagBit;u32]

AllocatorCreateFlagBit :: enum u32 {
	EXTERNALLY_SYNCHRONIZED    = 0,
	KHR_DEDICATED_ALLOCATION   = 1,
	KHR_BIND_MEMORY2           = 2,
	EXT_MEMORY_BUDGET          = 3,
	AMD_DEVICE_COHERENT_MEMORY = 4,
	BUFFER_DEVICE_ADDRESS      = 5,
	EXT_MEMORY_PRIORITY        = 6,
}

MemoryUsage :: enum u32 {
	UNKNOWN              = 0,
	GPU_ONLY             = 1,
	CPU_ONLY             = 2,
	CPU_TO_GPU           = 3,
	GPU_TO_CPU           = 4,
	CPU_COPY             = 5,
	GPU_LAZILY_ALLOCATED = 6,
	AUTO                 = 7,
	AUTO_PREFER_DEVICE   = 8,
	AUTO_PREFER_HOST     = 9,
}

AllocationCreateFlags :: distinct bit_set[AllocationCreateFlagBit;u32]


AllocationCreateFlagBit :: enum u32 {
	DEDICATED_MEMORY                   = 0,
	NEVER_ALLOCATE                     = 1,
	MAPPED                             = 2,
	USER_DATA_COPY_STRING              = 5,
	UPPER_ADDRESS                      = 6,
	DONT_BIND                          = 7,
	WITHIN_BUDGET                      = 8,
	CAN_ALIAS                          = 9,
	HOST_ACCESS_SEQUENTIAL_WRITE       = 10,
	HOST_ACCESS_RANDOM                 = 11,
	HOST_ACCESS_ALLOW_TRANSFER_INSTEAD = 12,
	STRATEGY_MIN_MEMORY                = 16,
	STRATEGY_MIN_TIME                  = 17,
	STRATEGY_MIN_OFFSET                = 18,
	STRATEGY_BEST_FIT                  = STRATEGY_MIN_MEMORY,
	STRATEGY_FIRST_FIT                 = STRATEGY_MIN_TIME,
	STRATEGY_MASK                      = STRATEGY_MIN_MEMORY | STRATEGY_MIN_TIME | STRATEGY_MIN_OFFSET,
}

PoolCreateFlags :: distinct bit_set[PoolCreateFlagBit;u32]

PoolCreateFlagBit :: enum u32 {
	IGNORE_BUFFER_IMAGE_GRANULARITY = 1,
	LINEAR_ALGORITHM                = 2,
	ALGORITHM_MASK                  = LINEAR_ALGORITHM,
}

DefragmentationFlags :: distinct bit_set[DefragmentationFlagBit;u32]


DefragmentationFlagBit :: enum u32 {
	ALGORITHM_FAST      = 0,
	ALGORITHM_BALANCED  = 1,
	ALGORITHM_FULL      = 2,
	ALGORITHM_EXTENSIVE = 3,
	ALGORITHM_MASK      = ALGORITHM_FAST | ALGORITHM_BALANCED | ALGORITHM_FULL | ALGORITHM_EXTENSIVE,
}

DefragmentationMoveOperation :: enum u32 {
	COPY    = 0,
	IGNORE  = 1,
	DESTROY = 2,
}

VirtualBlockCreateFlags :: distinct bit_set[VirtualBlockCreateFlagBit;u32]

VirtualBlockCreateFlagBit :: enum u32 {
	LINEAR_ALGORITHM = 1,
	ALGORITHM_MASK   = LINEAR_ALGORITHM,
}


VirtualAllocationCreateFlags :: distinct bit_set[VirtualAllocationCreateFlagBit;u32]

VirtualAllocationCreateFlagBit :: enum u32 {
	UPPER_ADDRESS       = 7,
	STRATEGY_MIN_MEMORY = 17,
	STRATEGY_MIN_TIME   = 18,
	STRATEGY_MIN_OFFSET = 19,
	STRATEGY_MASK       = STRATEGY_MIN_MEMORY | STRATEGY_MIN_TIME | STRATEGY_MIN_OFFSET,
}
