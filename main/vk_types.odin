package main

import "core:math"
import "core:math/linalg"
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

GPUMeshBuffers :: struct {
	index_buffer:          AllocatedBuffer,
	vertex_buffer:         AllocatedBuffer,
	vertex_buffer_address: vk.DeviceAddress,
}

// 256 bytes is the maximum allowed in a push constant on a 3090Ti
// TODO: move matrices out into uniform
#assert(size_of(GPUDrawPushConstants) <= 256)
GPUDrawPushConstants :: struct {
	global_data_buffer_address: vk.DeviceAddress, // ^GlobalData
	vertex_buffer_address:      vk.DeviceAddress, // ^Vertex
}

GPUGlobalData :: struct {
	view_projection_matrix:        hlsl.float4x4,
	view_projection_i_matrix:     hlsl.float4x4,
	sun_view_projection_matrix:    hlsl.float4x4,
	sun_view_projection_i_matrix: hlsl.float4x4,
	sun_color:                     hlsl.float3,
	bias: f32,
	sky_color:                     hlsl.float3,
	pad_0:                          f32,
	camera_pos : hlsl.float3,
	pad_1: f32,
	sun_pos : hlsl.float3,
	pad_2: f32,
}
