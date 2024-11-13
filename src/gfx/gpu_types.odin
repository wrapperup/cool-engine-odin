package gfx

import "core:math"
import "core:math/linalg"
import hlsl "core:math/linalg/hlsl"
import vma "deps:odin-vma"
import vk "vendor:vulkan"

@(ShaderShared)
Vertex :: struct {
	position: hlsl.float3,
	uv_x:     f32,
	normal:   hlsl.float3,
	uv_y:     f32,
	color:    hlsl.float4,
	tangent:  hlsl.float4,
}

@(ShaderShared)
SkeletonVertexAttribute :: struct {
	joints:  [4]u8,
	weights: [4]f32,
}

GPUMeshBuffers :: struct {
	index_buffer:  GPUBuffer,
	index_count:   u32,
	vertex_buffer: GPUBuffer,
	vertex_count:  u32,
}

GPUSkelMeshBuffers :: struct {
	using mesh_buffers:     GPUMeshBuffers,

	// Array of SkeletonVertexAttribute
	skel_vert_attrs_buffer: GPUBuffer,
	attrs_count:            u32,
}
