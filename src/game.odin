package main

import "core:math/linalg/hlsl"
import "core:time"

import glfw "vendor:glfw"
import vk "vendor:vulkan"

import gfx "gfx"


NUM_FRAME_AVG_COUNT :: 10

FrameTimeStats :: enum {
	Total,
	GameState,
	Imgui,
	Physics,
	Render,
}

Game :: struct {
	window:                     glfw.WindowHandle,
	window_extent:              [2]u32,
	frame_data:                 [gfx.FRAME_OVERLAP]GameFrameData,
	state:                      GameState,

	// Stats
	frame_times:                [len(FrameTimeStats)]f32,
	frame_times_smooth:         [len(FrameTimeStats)]f32,
	frame_times_start:          [len(FrameTimeStats)]time.Tick,
	delta_time:                 f64,
	live_time:                  f64,

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

@(deferred_in = end_scope_stat_time)
scope_stat_time :: proc(stat_type: FrameTimeStats) {
	start_scope_stat_time(stat_type)
}

start_scope_stat_time :: proc(stat_type: FrameTimeStats) {
	game.frame_times_start[stat_type] = time.tick_now()
}

end_scope_stat_time :: proc(stat_type: FrameTimeStats) {
	game.frame_times[stat_type] = f32(time.tick_since(game.frame_times_start[stat_type])) / f32(time.Millisecond)
}

game: Game
