package main

import "core:math/linalg/hlsl"
import "core:time"

import glfw "vendor:glfw"
import vk "vendor:vulkan"

import gfx "gfx"

Game :: struct {
	window:                     glfw.WindowHandle,
	frame_data:                 [gfx.FRAME_OVERLAP]GameFrameData,
	state:                      GameState,

	// Stats
	frame_time_total:           f32,
	frame_time_game_state:      f32,
	frame_time_physics:         f32,
	frame_time_render:          f32,
	delta_time:                 f64,
	live_time:                  f64,
	start_time:                 time.Tick,

	// Bindless textures, etc
	bindless_descriptor_layout: vk.DescriptorSetLayout,
	bindless_descriptor_set:    vk.DescriptorSet,

	// Mesh pipelines
	mesh_pipeline_layout:       vk.PipelineLayout,
	mesh_pipeline:              vk.Pipeline,
	// mesh_descriptor_set:    vk.DescriptorSet,
	// mesh_descriptor_layout: vk.DescriptorSetLayout,
	model_matrices:             [dynamic]hlsl.float4x4,
	sphere_mesh_buffers:        gfx.GPUMeshBuffers,
	TEMP_mesh_image:            gfx.AllocatedImage,

	// Skeletal mesh pipelines
	skel_mesh_pipeline_layout:  vk.PipelineLayout,
	skel_mesh_pipeline:         vk.Pipeline,
	skel_mesh_buffers:          gfx.GPUSkelMeshBuffers,
	skel:                       gfx.Skeleton,
	skel_anim:                  gfx.SkeletalAnimation,
	skel_animator:              gfx.SkeletonAnimator,
	use_game_time:              bool,
	sample_time:                f32,

	// Shadow pipelines
	mesh_shadow_pipeline:       vk.Pipeline,
	shadow_depth_image:         gfx.AllocatedImage,

	// Tonemapper pipelines
	tonemapper_pipeline:        vk.Pipeline,
	tonemapper_pipeline_layout: vk.PipelineLayout,
}

game: Game
