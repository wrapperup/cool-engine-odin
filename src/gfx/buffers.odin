package gfx

import "core:fmt"
import "core:mem"
import "core:slice"
import vma "deps:odin-vma"
import vk "vendor:vulkan"

GPUBuffer :: struct {
	buffer:     vk.Buffer,
	allocation: vma.Allocation,
	info:       vma.AllocationInfo,
	address:    vk.DeviceAddress,
}


// This allocates on the GPU, make sure to call `destroy_buffer` or add to deletion queue when you are finished with the buffer.
create_buffer :: proc(
	#any_int alloc_size: vk.DeviceSize, // TODO: Possible footgun? Idk, every other time it's annoying.
	usage: vk.BufferUsageFlags,
	memory_usage: vma.MemoryUsage,
	alloc_flags: vma.AllocationCreateFlags = {.MAPPED},
	loc := #caller_location,
	debug_name: cstring = nil,
) -> GPUBuffer {
	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
	}
	buffer_info.size = alloc_size
	buffer_info.usage = usage

	vma_alloc_info := vma.AllocationCreateInfo {
		usage = memory_usage,
		flags = alloc_flags,
	}

	new_buffer: GPUBuffer

	vk_check(
		vma.CreateBuffer(r_ctx.allocator, &buffer_info, &vma_alloc_info, &new_buffer.buffer, &new_buffer.allocation, &new_buffer.info),
		loc,
	)

	if .SHADER_DEVICE_ADDRESS in usage {
		new_buffer.address = get_buffer_device_address(new_buffer)
	}

	when ODIN_DEBUG {
		if debug_name == nil {
			debug_set_object_name(new_buffer.buffer, fmt.ctprint(loc))
		} else {
			debug_set_object_name(new_buffer.buffer, debug_name)
		}
	}

	return new_buffer
}

destroy_buffer :: proc(allocated_buffer: ^GPUBuffer) {
	vma.DestroyBuffer(r_ctx.allocator, allocated_buffer.buffer, allocated_buffer.allocation)
}

// Only purpose of this is to be captured during bindgen.
// TODO: Revisit this, I do want to generate shader bindings automatically...
// GPUPointer :: struct($T: typeid) {
// 	a: vk.DeviceAddress,
// }

get_buffer_device_address :: proc(buffer: GPUBuffer) -> vk.DeviceAddress {
	device_address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buffer.buffer,
	}

	return vk.GetBufferDeviceAddress(r_ctx.device, &device_address_info)
}

// Writes to the buffer with the input data at offset.
write_buffer :: proc(buffer: ^GPUBuffer, in_data: ^$T, offset: vk.DeviceSize = 0, loc := #caller_location) {
	size := size_of(T)
	assert(buffer.info.size >= vk.DeviceSize(u64(size) + u64(offset)), "The size of the data and offset is larger than the buffer", loc)

	data := cast([^]u8)buffer.info.pMappedData
	mem.copy(data[offset:], in_data, size)
}

// Writes to the buffer with the input slice at offset.
write_buffer_slice :: proc(buffer: ^GPUBuffer, in_data: []$T, offset: vk.DeviceSize = 0, loc := #caller_location) {
	size := size_of(T) * len(in_data)
	assert(buffer.info.size >= vk.DeviceSize(u64(size) + u64(offset)), "The size of the slice and offset is larger than the buffer", loc)

	data := cast([^]u8)buffer.info.pMappedData
	mem.copy(data[offset:], raw_data(in_data), size)
}

// Uploads the data via a staging buffer. This is useful if your buffer is GPU only.
staging_write_buffer :: proc(buffer: ^GPUBuffer, in_data: ^$T, offset: vk.DeviceSize = 0, loc := #caller_location) {
	size := size_of(T)
	assert(buffer.info.size >= vk.DeviceSize(u64(size) + u64(offset)), "The size of the data and offset is larger than the buffer", loc)

	staging := create_buffer(vk.DeviceSize(size_of(T)), {.TRANSFER_SRC}, .CPU_ONLY)
	write_buffer(&staging, in_data)

	if cmd, ok := immediate_submit(); ok {
		region := vk.BufferCopy {
			dstOffset = offset,
			srcOffset = 0,
			size      = vk.DeviceSize(size),
		}

		vk.CmdCopyBuffer(cmd, staging.buffer, buffer.buffer, 1, &region)
	}

	destroy_buffer(&staging)
}

// Uploads the data via a staging buffer. This is useful if your buffer is GPU only.
staging_write_buffer_slice :: proc(buffer: ^GPUBuffer, in_data: []$T, offset: vk.DeviceSize = 0, loc := #caller_location) {
	size := size_of(T) * len(in_data)
	assert(buffer.info.size >= vk.DeviceSize(u64(size) + u64(offset)), "The size of the slice and offset is larger than the buffer", loc)

	staging := create_buffer(vk.DeviceSize(size), {.TRANSFER_SRC}, .CPU_ONLY)
	write_buffer_slice(&staging, in_data)

	if cmd, ok := immediate_submit(); ok {
		region := vk.BufferCopy {
			dstOffset = offset,
			srcOffset = 0,
			size      = vk.DeviceSize(size),
		}

		vk.CmdCopyBuffer(cmd, staging.buffer, buffer.buffer, 1, &region)
	}

	destroy_buffer(&staging)
}

transition_buffer :: proc(
	cmd: vk.CommandBuffer,
	buffer: GPUBuffer,
	src_flags: vk.AccessFlags2,
	dst_flags: vk.AccessFlags2,
	queue_family_index: u32,
) {
	buffer_memory_barrier := vk.BufferMemoryBarrier2 {
		sType               = .BUFFER_MEMORY_BARRIER_2,
		pNext               = nil,
		srcStageMask        = {.ALL_COMMANDS},
		srcAccessMask       = src_flags,
		dstStageMask        = {.ALL_COMMANDS},
		dstAccessMask       = dst_flags,
		buffer              = buffer.buffer,
		size                = buffer.info.size,
		srcQueueFamilyIndex = queue_family_index,
		dstQueueFamilyIndex = queue_family_index,
	}

	dep_info := vk.DependencyInfo {
		sType                    = .DEPENDENCY_INFO,
		pNext                    = nil,
		bufferMemoryBarrierCount = 1,
		pBufferMemoryBarriers    = &buffer_memory_barrier,
	}

	vk.CmdPipelineBarrier2(cmd, &dep_info)
}

// TODO: Do we need this? It would be useful I think at some point.
// It's specific push/pop functions will update a buffer automatically,
// and maps to an Odin dynamic array.
GPUDynamicArray :: struct {
	using _: GPUBuffer,
}
