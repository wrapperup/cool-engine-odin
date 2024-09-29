package gfx

import "core:fmt"
import vk "vendor:vulkan"

DescriptorBinding :: struct {
	binding: u32,
	type:    vk.DescriptorType,
}

create_descriptor_set_layout :: proc(
	device: vk.Device,
	stage_flags: vk.ShaderStageFlags = {},
	bindings: [$N]DescriptorBinding,
	descriptor_count: u32 = 1,
	descriptor_set_layout_flags: vk.DescriptorSetLayoutCreateFlags = {},
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
	vk_check(vk.CreateDescriptorSetLayout(device, &info, nil, &set))

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
		result = vk.AllocateDescriptorSets(device, &alloc_info, &descriptor_set)

		fmt.println(result)

		vk_check(result)
	}

	return descriptor_set
}

destroy_descriptor_allocator :: proc(allocator: ^DescriptorAllocator) {
	delete(allocator.pool_ratios)
	delete(allocator.ready_pools)
	delete(allocator.full_pools)
}

DescriptorWrite :: union {
	DescriptorWriteImage,
	DescriptorWriteBuffer,
}

DescriptorWriteImage :: struct {
	binding:      u32,
	type:         vk.DescriptorType,
	image_view:   vk.ImageView,
	sampler:      vk.Sampler,
	image_layout: vk.ImageLayout,
}

DescriptorWriteBuffer :: struct {
	binding: u32,
	type:    vk.DescriptorType,
	buffer:  vk.Buffer,
}

write_descriptor_set :: proc(device: vk.Device, descriptor_set: vk.DescriptorSet, writes: []DescriptorWrite) {
	// Collect writes in the convenient format into vk's.
	descriptor_writes: [dynamic]vk.WriteDescriptorSet
	image_infos: [dynamic]vk.DescriptorImageInfo
	buffer_infos: [dynamic]vk.DescriptorBufferInfo

	for write in writes {
		switch v in write {
		case DescriptorWriteImage:
			image_info := vk.DescriptorImageInfo {
				imageLayout = v.image_layout,
				imageView   = v.image_view,
				sampler     = v.sampler,
			}

			append(&image_infos, image_info)

			descriptor_write := vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				pNext           = nil,
				dstBinding      = v.binding,
				dstSet          = descriptor_set,
				descriptorCount = 1,
				descriptorType  = v.type,
				pImageInfo      = &image_infos[len(image_infos) - 1],
			}

			append(&descriptor_writes, descriptor_write)

		case DescriptorWriteBuffer:
			buffer_info := vk.DescriptorBufferInfo {
				buffer = v.buffer,
			}

			append(&buffer_infos, buffer_info)

			descriptor_write := vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				pNext           = nil,
				dstBinding      = v.binding,
				dstSet          = descriptor_set,
				descriptorCount = 1,
				descriptorType  = v.type,
				pBufferInfo     = &buffer_infos[len(buffer_infos) - 1],
			}

			append(&descriptor_writes, descriptor_write)
		}
	}

	// Finally write out all of the writes
	vk.UpdateDescriptorSets(device, u32(len(descriptor_writes)), raw_data(descriptor_writes), 0, nil)

	// TODO: cleanup?
}
