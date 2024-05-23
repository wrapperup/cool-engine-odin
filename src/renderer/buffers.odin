package renderer

import "core:mem"
import vk "vendor:vulkan"
import "core:fmt"
import vma "deps:odin-vma"

// This allocates on the GPU, make sure to call `destroy_buffer` when you are finished with the buffer.
create_buffer :: proc(
	engine: ^VulkanEngine,
	alloc_size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.MemoryUsage,
	alloc_flags: vma.AllocationCreateFlags = {.MAPPED},
) -> AllocatedBuffer {
	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
	}
	buffer_info.size = alloc_size
	buffer_info.usage = usage

	vma_alloc_info := vma.AllocationCreateInfo {
		usage = memory_usage,
		flags = alloc_flags,
	}

	new_buffer: AllocatedBuffer

	vk_check(
		vma.CreateBuffer(
			engine.allocator,
			&buffer_info,
			&vma_alloc_info,
			&new_buffer.buffer,
			&new_buffer.allocation,
			&new_buffer.info,
		),
	)

	return new_buffer
}

destroy_buffer :: proc(engine: ^VulkanEngine, allocated_buffer: ^AllocatedBuffer) {
	vma.DestroyBuffer(engine.allocator, allocated_buffer.buffer, allocated_buffer.allocation)
}

create_mesh_buffers :: proc(engine: ^VulkanEngine, indices: []u32, vertices: []Vertex) -> GPUMeshBuffers {
	vertex_buffer_size := vk.DeviceSize(size_of(Vertex) * len(vertices))
	index_buffer_size := vk.DeviceSize(size_of(u32) * len(indices))

	new_surface: GPUMeshBuffers

	new_surface.vertex_buffer = create_buffer(
		engine,
		vertex_buffer_size,
		{.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
		.GPU_ONLY,
	)

	device_address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = new_surface.vertex_buffer.buffer,
	}
	new_surface.vertex_buffer_address = vk.GetBufferDeviceAddress(engine.device, &device_address_info)

	new_surface.index_buffer = create_buffer(engine, index_buffer_size, {.INDEX_BUFFER, .TRANSFER_DST}, .GPU_ONLY)

	staging := create_buffer(engine, vertex_buffer_size + index_buffer_size, {.TRANSFER_SRC}, .CPU_ONLY)

	data := staging.info.pMappedData

	// TODO: Make these slices somehow? maybe make a helper method for staging buffers?
	mem.copy(data, raw_data(vertices), int(vertex_buffer_size))
	mem.copy(mem.ptr_offset((^u8)(data), vertex_buffer_size), raw_data(indices), int(index_buffer_size))

	if cmd, ok := immediate_submit(engine); ok {
		vertex_copy := vk.BufferCopy {
			dstOffset = 0,
			srcOffset = 0,
			size      = vertex_buffer_size,
		}

		vk.CmdCopyBuffer(cmd, staging.buffer, new_surface.vertex_buffer.buffer, 1, &vertex_copy)

		index_copy := vk.BufferCopy {
			dstOffset = 0,
			srcOffset = vertex_buffer_size,
			size      = index_buffer_size,
		}

		vk.CmdCopyBuffer(cmd, staging.buffer, new_surface.index_buffer.buffer, 1, &index_copy)
	}

	destroy_buffer(engine, &staging)

	return new_surface
}

write_buffer :: proc(buffer: ^AllocatedBuffer, in_data: ^GPUGlobalData) {
	data := buffer.info.pMappedData
	mem.copy(data, in_data, size_of(GPUGlobalData))
}
