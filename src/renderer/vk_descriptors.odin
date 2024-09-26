package renderer

import "core:fmt"
import vk "vendor:vulkan"

DescriptorBinding :: struct {
	binding: u32,
	type:    vk.DescriptorType,
}

create_descriptor_set_layout :: proc(
	engine: ^VulkanEngine,
	bindings: [$N]DescriptorBinding,
	stage_flags: vk.ShaderStageFlags = {},
	descriptor_set_layout_flags: vk.DescriptorSetLayoutCreateFlags = {},
	descriptor_count: u32 = 1,
) -> vk.DescriptorSetLayout {
	descriptor_set_bindings := [N]vk.DescriptorSetLayoutBinding{}

	for binding, i in bindings {
		descriptor_set_bindings[i] = vk.DescriptorSetLayoutBinding {
			stageFlags      = stage_flags,
			binding         = binding.binding,
			descriptorType  = binding.type,
			descriptorCount = descriptor_count,
		}
	}

	info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pBindings    = raw_data(descriptor_set_bindings[:]),
		bindingCount = u32(len(descriptor_set_bindings)),
		flags        = descriptor_set_layout_flags,
	}

	set: vk.DescriptorSetLayout
	vk_check(vk.CreateDescriptorSetLayout(engine.device, &info, nil, &set))

	return set
}

DescriptorAllocator :: struct {
	sets_per_pool: u32,
	pool_ratios:   [dynamic]PoolSizeRatio,
	ready_pools:   [dynamic]vk.DescriptorPool,
	full_pools:    [dynamic]vk.DescriptorPool,
	flags:         vk.DescriptorPoolCreateFlags,
}

PoolSizeRatio :: struct {
	type:  vk.DescriptorType,
	ratio: f32,
}

init_descriptor_allocator :: proc(
	allocator: ^DescriptorAllocator,
	device: vk.Device,
	max_sets: u32,
	pool_ratios: []PoolSizeRatio,
	flags: vk.DescriptorPoolCreateFlags = {},
) {
	clear(&allocator.pool_ratios)

	for &ratio in pool_ratios {
		append(&allocator.pool_ratios, ratio)
	}

	new_pool := create_pool(allocator, device, max_sets, pool_ratios, flags)
	allocator.flags = flags

	append(&allocator.ready_pools, new_pool)
}

get_pool :: proc(allocator: ^DescriptorAllocator, device: vk.Device) -> vk.DescriptorPool {
	if len(allocator.ready_pools) > 0 {
		return pop(&allocator.ready_pools)
	} else {
		return create_pool(allocator, device, allocator.sets_per_pool, allocator.pool_ratios[:], allocator.flags)
	}
}

create_pool :: proc(
	allocator: ^DescriptorAllocator,
	device: vk.Device,
	set_count: u32,
	pool_ratios: []PoolSizeRatio,
	flags: vk.DescriptorPoolCreateFlags = {},
) -> vk.DescriptorPool {
	pool_sizes: [dynamic]vk.DescriptorPoolSize
	defer delete(pool_sizes)

	reserve(&pool_sizes, len(pool_ratios))

	for ratio, i in pool_ratios {
		append(
			&pool_sizes,
			vk.DescriptorPoolSize{type = ratio.type, descriptorCount = u32(f32(ratio.ratio) * f32(set_count))},
		)
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = flags,
		maxSets       = set_count,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = raw_data(pool_sizes),
	}

	new_pool: vk.DescriptorPool
	vk_check(vk.CreateDescriptorPool(device, &pool_info, nil, &new_pool))

	return new_pool
}

reset_pools :: proc(allocator: ^DescriptorAllocator, device: vk.Device) {
	for &pool in &allocator.ready_pools {
		vk.ResetDescriptorPool(device, pool, {})
	}

	for &pool in &allocator.full_pools {
		vk.ResetDescriptorPool(device, pool, {})
		append(&allocator.ready_pools, pool)
	}
	clear(&allocator.full_pools)
}

destroy_pools :: proc(allocator: ^DescriptorAllocator, device: vk.Device) {
	for &pool in &allocator.ready_pools {
		vk.DestroyDescriptorPool(device, pool, nil)
	}
	clear(&allocator.ready_pools)

	for &pool in &allocator.full_pools {
		vk.DestroyDescriptorPool(device, pool, nil)
	}
	clear(&allocator.full_pools)
}

allocate_descriptor_set :: proc(
	allocator: ^DescriptorAllocator,
	device: vk.Device,
	layout: vk.DescriptorSetLayout,
) -> vk.DescriptorSet {
	pool := get_pool(allocator, device)
	layout := layout

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = nil,
		descriptorPool     = pool,
		descriptorSetCount = 1,
		pSetLayouts        = &layout,
	}

	descriptor_set: vk.DescriptorSet
	result := vk.AllocateDescriptorSets(device, &alloc_info, &descriptor_set)

	if result == .ERROR_OUT_OF_POOL_MEMORY || result == .ERROR_FRAGMENTED_POOL {
		append(&allocator.full_pools, pool)

		pool = get_pool(allocator, device)
		alloc_info.descriptorPool = pool

		// Try again, if it fails then we're goofed anyway.
		vk_check(vk.AllocateDescriptorSets(device, &alloc_info, &descriptor_set))
	}

	return descriptor_set
}

destroy_descriptor_allocator :: proc(allocator: ^DescriptorAllocator) {
	delete(allocator.pool_ratios)
	delete(allocator.ready_pools)
	delete(allocator.full_pools)
}
