package main

import vk "vendor:vulkan"

DescriptorBinding :: struct {
	binding: u32,
	type:    vk.DescriptorType,
}

PoolSizeRatio :: struct {
	type:  vk.DescriptorType,
	ratio: f32,
}

DescriptorAllocator :: struct {
	pool: vk.DescriptorPool,
}


create_descriptor_set_layout :: proc(
	engine: ^VulkanEngine,
	bindings: [$N]DescriptorBinding,
	flags: vk.ShaderStageFlags = {},
) -> vk.DescriptorSetLayout {
	descriptor_set_bindings := [N]vk.DescriptorSetLayoutBinding{}

	for binding, i in bindings {
		descriptor_set_bindings[i] = vk.DescriptorSetLayoutBinding {
			stageFlags      = flags,
			binding         = binding.binding,
			descriptorType  = binding.type,
			descriptorCount = 1,
		}
	}

	info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pBindings    = raw_data(descriptor_set_bindings[:]),
		bindingCount = u32(len(descriptor_set_bindings)),
	}

	set: vk.DescriptorSetLayout
	vk_check(vk.CreateDescriptorSetLayout(engine.device, &info, nil, &set))

	return set
}

init_pool :: proc(allocator: ^DescriptorAllocator, device: vk.Device, max_sets: u32, pool_ratios: []PoolSizeRatio) {
	pool_sizes: [dynamic]vk.DescriptorPoolSize
	defer delete(pool_sizes)

	resize(&pool_sizes, len(pool_ratios))

	for ratio in pool_ratios {
		append(
			&pool_sizes,
			vk.DescriptorPoolSize{type = ratio.type, descriptorCount = u32(ratio.ratio * f32(max_sets))},
		)
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
	}
	pool_info.flags = {}
	pool_info.maxSets = max_sets
	pool_info.poolSizeCount = u32(len(pool_sizes))
	pool_info.pPoolSizes = raw_data(pool_sizes)

	vk.CreateDescriptorPool(device, &pool_info, nil, &allocator.pool)
}

clear_descriptors :: proc(allocator: ^DescriptorAllocator, device: vk.Device) {
	vk.ResetDescriptorPool(device, allocator.pool, {})
}

destroy_pool :: proc(allocator: ^DescriptorAllocator, device: vk.Device) {
	vk.DestroyDescriptorPool(device, allocator.pool, nil)
}

allocate_pool :: proc(
	allocator: ^DescriptorAllocator,
	device: vk.Device,
	layout: vk.DescriptorSetLayout,
) -> vk.DescriptorSet {
	layout := layout

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
	}

	alloc_info.pNext = nil
	alloc_info.descriptorPool = allocator.pool
	alloc_info.descriptorSetCount = 1
	alloc_info.pSetLayouts = &layout

	ds: vk.DescriptorSet
	vk_check(vk.AllocateDescriptorSets(device, &alloc_info, &ds))

	return ds
}
