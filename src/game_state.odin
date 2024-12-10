package game

import "base:intrinsics"
import "core:/math/linalg/hlsl"
import "core:fmt"
import "core:math/linalg"
import "core:time"

import glfw "vendor:glfw"
import vk "vendor:vulkan"

import px "deps:physx-odin"

import gfx "gfx"

NUM_FRAME_AVG_COUNT :: 10

FrameTimeStats :: enum {
	Total,
	GameState,
	Imgui,
	Physics,
	Render,
}

PhysicsContext :: struct {
	foundation:         ^px.Foundation,
	dispatcher:         ^px.DefaultCpuDispatcher,
	physics:            ^px.Physics,
	scene:              ^px.Scene,
	controller_manager: ^px.ControllerManager,
}

ViewState :: enum {
	SceneColor,
	SceneDepth,
	ShadowDepth,
}

SkeletalMeshInstance :: struct {
	preskinned_vertex_buffers: [gfx.FRAME_OVERLAP]gfx.GPUBuffer,
	joint_matrices_buffers:    [gfx.FRAME_OVERLAP]gfx.GPUBuffer,
	skel:                      ^Skeleton,
}

init_skeletal_mesh_instance :: proc(skel: ^Skeleton, anim: ^SkeletalAnimation) -> SkeletalMeshInstance {
	instance := SkeletalMeshInstance {
		skel = skel,
	}

	for i in 0 ..< gfx.FRAME_OVERLAP {
		instance.joint_matrices_buffers[i] = gfx.create_buffer(
			vk.DeviceSize(size_of(hlsl.float4x4) * instance.skel.joint_count),
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)
		instance.preskinned_vertex_buffers[i] = gfx.create_buffer(
			vk.DeviceSize(instance.skel.buffers.vertex_count * size_of(Vertex)),
			{.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
			.GPU_ONLY,
		)

		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, instance.joint_matrices_buffers[i])
		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, instance.preskinned_vertex_buffers[i])
	}

	return instance
}

Game :: struct {
	window:             glfw.WindowHandle,
	window_extent:      [2]u32,
	state:              GameState,
	renderer:           ^gfx.Renderer,
	input_manager:      ^InputManager,
	view_state:         ViewState,
	render_state:       RenderState,

	// Entity storage
	entity_storage:     ^EntityStorage,

	// Physics
	phys:               PhysicsContext,

	// Stats
	frame_times:        [len(FrameTimeStats)]f32,
	frame_times_smooth: [len(FrameTimeStats)]f32,
	frame_times_start:  [len(FrameTimeStats)]time.Tick,
	frame_time_start:   time.Tick,
	delta_time:         f64,
	live_time:          f64,
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

GameState :: struct {
	environment: Environment,
	player_id:   TypedEntityId(Player),
}

Environment :: struct {
	sun_color:  hlsl.float3,
	sky_color:  hlsl.float3,
	bias:       f32,
	sun_pos:    [3]f32,
	sun_target: [3]f32,
}

PlayerController :: struct {
	input: struct {
		forward: bool,
		back:    bool,
		left:    bool,
		right:   bool,
		jump:    bool,
		crouch:  bool,
	},
}
