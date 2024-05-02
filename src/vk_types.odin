package main

import hlsl "core:math/linalg/hlsl"
import vma "deps:odin-vma"
import vk "vendor:vulkan"

AllocatedImage :: struct {
	image:      vk.Image,
	image_view: vk.ImageView,
	allocation: vma.Allocation,
	extent:     vk.Extent3D,
	format:     vk.Format,
}

AllocatedBuffer :: struct {
	buffer:     vk.Buffer,
	allocation: vma.Allocation,
	info:       vma.AllocationInfo,
}

Vertex :: struct {
	position: hlsl.float3,
	uv_x:     f32,
	normal:   hlsl.float3,
	uv_y:     f32,
	color:    hlsl.float4,
}

#assert(size_of(GPUDrawPushConstants) <= 256)
GPUDrawPushConstants :: struct {
	view_matrix:       hlsl.float4x4,
	view_it_matrix:    hlsl.float4x4,
	projection_matrix: hlsl.float4x4,
	voxel_buffer:      vk.DeviceAddress, // ^PackedVoxelData
}

#assert(size_of(ComputePushConstants) <= 256)
ComputePushConstants :: struct {
	voxel_buffer:     vk.DeviceAddress, // ^PackedVoxelData
	draw_cmds_buffer: vk.DeviceAddress, // ^vk.DrawIndirectCommand
	frame_time:       u32,
}
