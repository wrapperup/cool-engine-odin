package main

import "core:math/linalg/hlsl"

import glfw "vendor:glfw"
import vk "vendor:vulkan"

import gfx "gfx"

Game :: struct {
	window:                 glfw.WindowHandle,
	frame_data:             [gfx.FRAME_OVERLAP]GameFrameData,
	state:                  GameState,

	// Stats
	frame_time_total:       f32,
	frame_time_game_state:  f32,
	frame_time_physics:     f32,
	frame_time_render:      f32,
	delta_time:             f64,

	// Mesh pipelines
	mesh_pipeline_layout:   vk.PipelineLayout,
	mesh_pipeline:          vk.Pipeline,
	mesh_descriptor_set:    vk.DescriptorSet,
	mesh_descriptor_layout: vk.DescriptorSetLayout,
	model_matrices:         [dynamic]hlsl.float4x4,
	mesh_buffers:           gfx.GPUMeshBuffers,
	sphere_mesh_buffers:    gfx.GPUMeshBuffers,
	TEMP_mesh_image:        gfx.AllocatedImage,

	// Shadow pipelines
	mesh_shadow_pipeline:   vk.Pipeline,
	shadow_depth_image:     gfx.AllocatedImage,
}

game: Game
