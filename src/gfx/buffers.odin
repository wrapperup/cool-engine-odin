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
	alloc_size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.MemoryUsage,
	alloc_flags: vma.AllocationCreateFlags = {.MAPPED},
	loc := #caller_location,
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

	return new_buffer
}

destroy_buffer :: proc(allocated_buffer: ^GPUBuffer) {
	vma.DestroyBuffer(r_ctx.allocator, allocated_buffer.buffer, allocated_buffer.allocation)
}

// Only purpose of this is to be captured during bindgen.
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

create_mesh_buffers :: proc(index_count: u32, vertex_count: u32) -> GPUMeshBuffers {
	assert(index_count > 0)
	assert(vertex_count > 0)

	vertex_buffer_size := vk.DeviceSize(size_of(Vertex) * vertex_count)
	index_buffer_size := vk.DeviceSize(size_of(u32) * index_count)

	new_surface: GPUMeshBuffers
	new_surface.index_count = index_count
	new_surface.vertex_count = vertex_count

	new_surface.vertex_buffer = create_buffer(vertex_buffer_size, {.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS}, .GPU_ONLY)
	new_surface.index_buffer = create_buffer(index_buffer_size, {.INDEX_BUFFER, .TRANSFER_DST}, .GPU_ONLY)

	return new_surface
}

staging_write_mesh_buffers :: proc(buffers: ^GPUMeshBuffers, indices: []u32, vertices: []Vertex) {
	vertex_buffer_size := vk.DeviceSize(size_of(Vertex) * len(vertices))
	index_buffer_size := vk.DeviceSize(size_of(u32) * len(indices))

	assert(buffers.index_count == u32(len(indices)))
	assert(buffers.vertex_count == u32(len(vertices)))

	staging := create_buffer(vertex_buffer_size + index_buffer_size, {.TRANSFER_SRC}, .CPU_ONLY)

	data := cast([^]u8)staging.info.pMappedData

	mem.copy(data, raw_data(vertices), int(vertex_buffer_size))
	mem.copy(data[vertex_buffer_size:], raw_data(indices), int(index_buffer_size))

	write_buffer_slice(&staging, vertices)
	write_buffer_slice(&staging, indices, vertex_buffer_size)

	if cmd, ok := immediate_submit(); ok {
		vertex_copy := vk.BufferCopy {
			dstOffset = 0,
			srcOffset = 0,
			size      = vertex_buffer_size,
		}

		vk.CmdCopyBuffer(cmd, staging.buffer, buffers.vertex_buffer.buffer, 1, &vertex_copy)

		index_copy := vk.BufferCopy {
			dstOffset = 0,
			srcOffset = vertex_buffer_size,
			size      = index_buffer_size,
		}

		vk.CmdCopyBuffer(cmd, staging.buffer, buffers.index_buffer.buffer, 1, &index_copy)
	}

	destroy_buffer(&staging)
}

// Writes to the buffer with the input data at offset.
write_buffer :: proc(buffer: ^GPUBuffer, in_data: ^$T, offset: vk.DeviceSize = 0) {
	size := size_of(T)
	assert(buffer.info.size >= vk.DeviceSize(u64(size) + u64(offset)), "The size of the data and offset is larger than the buffer")

	data := cast([^]u8)buffer.info.pMappedData
	mem.copy(data[offset:], in_data, size)
}

// Writes to the buffer with the input slice at offset.
write_buffer_slice :: proc(buffer: ^GPUBuffer, in_data: []$T, offset: vk.DeviceSize = 0) {
	size := size_of(T) * len(in_data)
	assert(buffer.info.size >= vk.DeviceSize(u64(size) + u64(offset)), "The size of the slice and offset is larger than the buffer")

	data := cast([^]u8)buffer.info.pMappedData
	mem.copy(data[offset:], raw_data(in_data), size)
}

// Uploads the data via a staging buffer. This is useful if your buffer is GPU only.
staging_write_buffer :: proc(buffer: ^GPUBuffer, in_data: ^$T, offset: vk.DeviceSize = 0) {
	size := size_of(T)
	assert(buffer.info.size >= vk.DeviceSize(u64(size) + u64(offset)), "The size of the data and offset is larger than the buffer")

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
staging_write_buffer_slice :: proc(buffer: ^GPUBuffer, in_data: []$T, offset: vk.DeviceSize = 0) {
	size := size_of(T) * len(in_data)
	assert(buffer.info.size >= vk.DeviceSize(u64(size) + u64(offset)), "The size of the slice and offset is larger than the buffer")

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

GPUDynamicArray :: struct {
	using GPUBuffer
}
