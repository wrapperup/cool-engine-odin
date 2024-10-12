package gfx

import "core:math"
import "core:math/linalg"
import hlsl "core:math/linalg/hlsl"
import vma "deps:odin-vma"
import vk "vendor:vulkan"

AllocatedBuffer :: struct {
	buffer:     vk.Buffer,
	allocation: vma.Allocation,
	info:       vma.AllocationInfo,
}

@(ShaderShared)
Vertex :: struct {
	position: hlsl.float3,
	uv_x:     f32,
	normal:   hlsl.float3,
	uv_y:     f32,
	color:    hlsl.float4,
}

@(ShaderShared)
SkeletonVertexAttribute :: struct {
	joints:  [4]u8,
	weights: [4]f32,
}

GPUMeshBuffers :: struct {
	index_buffer:   AllocatedBuffer,
	index_count:    u32,
	vertex_buffer:  AllocatedBuffer,
	vertex_address: vk.DeviceAddress,
}

GPUSkelMeshBuffers :: struct {
	using mesh_buffers:            GPUMeshBuffers,

	// Array of SkeletonVertexAttribute
	skel_vert_attrs_buffer:        AllocatedBuffer,
	skel_vert_attrs_address:       vk.DeviceAddress,
}
