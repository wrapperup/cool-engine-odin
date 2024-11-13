package game

import "base:runtime"
import "core:c"
import "core:dynlib"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:os"
import "core:sys/windows"
import "core:time"

import glfw "vendor:glfw"

import im "deps:odin-imgui"
import im_glfw "deps:odin-imgui/imgui_impl_glfw"
import im_vk "deps:odin-imgui/imgui_impl_vulkan"
import px "deps:physx-odin"

import "gfx"

start_live_time := time.tick_now()

game: ^Game

@(export)
game_init :: proc(window: glfw.WindowHandle) {
	game = new(Game)
	fmt.println(window)
	glfw.Init()

	game.window = window
	game.window_extent = {1920, 1080}

	game.renderer = gfx.init({window = game.window, msaa_samples = ._4, enable_validation_layers = true, enable_logs = true})
	if game.renderer == nil {
		fmt.println("Graphics could not be initialized.")
	}

	game.entity_storage = init_entity_storage()
	game.input_manager = init_input_manager()

	game_hot_reloaded(game)

	configure_im()

	init_physics()
	init_game_renderer()
	init_input()
	init_game_state()

	game.frame_time_start = time.tick_now()
}

@(export)
game_init_window :: proc() -> glfw.WindowHandle {
	glfw.Init()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	window := glfw.CreateWindow(1920, 1080, "Vulkan", nil, nil)

	fmt.println(window)

	return window
}

@(export)
game_memory :: proc() -> rawptr {
	return game
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(game)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	glfw.Init()

	game = cast(^Game)mem
	glfw.MakeContextCurrent(game.window)
	gfx.set_renderer(game.renderer)
	set_entity_storage(game.entity_storage)
	set_input_manager(game.input_manager)
	lock_mouse(game.input_manager.mouse_locked)

	gfx.load_vulkan_addresses()

	im.SetCurrentContext(gfx.renderer().imgui_ctx)

	fmt.println("Hot reloaded!")
}

init_input :: proc() {
	add_action_key_mapping(.Jump, glfw.KEY_SPACE)
	add_action_mouse_mapping(.Fire, glfw.MOUSE_BUTTON_LEFT)
	add_action_key_mapping(.LockCamera, glfw.KEY_M)
	add_action_key_mapping(.ExitGame, glfw.KEY_ESCAPE)

	add_axis_key_mapping(.MoveForward, glfw.KEY_W, 1.0)
	add_axis_key_mapping(.MoveForward, glfw.KEY_S, -1.0)
	add_axis_key_mapping(.MoveRight, glfw.KEY_D, 1.0)
	add_axis_key_mapping(.MoveRight, glfw.KEY_A, -1.0)

	add_axis_mouse_axis(.LookRight, mouse_x = true)
	add_axis_mouse_axis(.LookUp, mouse_y = true)
}

init_physics :: proc() {
	using px

	game.phys.foundation = create_foundation_ext()
	game.phys.dispatcher = default_cpu_dispatcher_create(1, nil, px.DefaultCpuDispatcherWaitForWorkMode.WaitForWork, 0)

	game.phys.physics = create_physics_ext(game.phys.foundation)

	callback_info := SimulationEventCallbackInfo {
		collision_callback        = collision_callback,
		trigger_callback          = trigger_callback,
		constraint_break_callback = constraint_break_callback,
		wake_sleep_callback       = wake_sleep_callback,
		advance_callback          = advance_callback,
	}

	callback := create_simulation_event_callbacks(&callback_info)

	scene_desc := scene_desc_new(tolerances_scale_new(1.0, 10.0))
	scene_desc.gravity = vec3_new_3(0.0, -9.81 * 2, 0.0)
	scene_desc.cpuDispatcher = game.phys.dispatcher
	scene_desc.simulationEventCallback = callback

	enable_custom_filter_shader(&scene_desc, collision_filter_shader, 1)

	game.phys.scene = physics_create_scene_mut(game.phys.physics, scene_desc)

	game.phys.controller_manager = create_controller_manager(game.phys.scene, false)

	// create a ground plane to the scene
	ground_material := physics_create_material_mut(game.phys.physics, 0.5, 0.5, 0.3)
	ground_plane := create_plane(game.phys.physics, plane_new_1(0.0, 1.0, 0.0, 0.0), ground_material)
	scene_add_actor_mut(game.phys.scene, ground_plane, nil)

	ground_wall := create_plane(
		game.phys.physics,
		plane_new_3(px.Vec3{-100, 0, 0}, transmute(px.Vec3)linalg.normalize([3]f32{1.0, 1.0, 0.0})),
		ground_material,
	)
	ground_wall2 := create_plane(
		game.phys.physics,
		plane_new_3(px.Vec3{100, 0, 0}, transmute(px.Vec3)linalg.normalize([3]f32{-1.0, 4.0, 0.0})),
		ground_material,
	)
	scene_add_actor_mut(game.phys.scene, ground_wall, nil)
	scene_add_actor_mut(game.phys.scene, ground_wall2, nil)

	scene_set_visualization_culling_box_mut(game.phys.scene, bounds3_new_1({-50, -50, -50}, {50, 50, 50}))
}

init_game_state :: proc() {
	game.render_state.draw_skybox = true

	camera := new_entity(Camera)
	init_camera(camera)
	camera.translation = {3, 3.7, 5}
	camera.camera_rot = {-0.4, -0.6, 0}
	camera.camera_fov_deg = 65

	grid_size: f32 = 3.0

	skeleton, anim, ok := gfx.load_skel_mesh_from_file("assets/meshes/skel/materialball.glb")
	// buffers, skeleton, anim, ok := gfx.load_skel_mesh_from_file("assets/meshes/skel/skeltest2.glb")
	assert(ok)

	// LEAK: Needs asset system.
	skel_ptr := new(gfx.Skeleton)
	skel_ptr^ = skeleton

	// LEAK: Needs asset system.
	anim_ptr := new(gfx.SkeletalAnimation)
	anim_ptr^ = anim

	for i in 0 ..< grid_size / 2 {
		for j in 0 ..< grid_size * 4 {
			for k in 0 ..< grid_size / 2 {
				ball := new_entity(Ball)
				init_ball(ball, {i * 3, j * 3, k * 3}, {}, skel_ptr, anim_ptr)
			}
		}
	}

	test_mesh := new_entity(StaticMesh)
	init_static_mesh(test_mesh, "assets/meshes/static/cube.glb", 1)

	game.state = GameState {
		camera_id = entity_id_of(camera),
		environment = Environment {
			sun_pos = {12, 15, 10},
			sun_target = 0.0,
			sun_color = 2.0,
			sky_color = 1.0,
			bias = 0.001,
		},
	}
}

@(export)
game_update :: proc() -> bool {
	scope_stat_time(.Total)

	game.live_time = f64(time.tick_since(start_live_time)) / f64(time.Second)

	game.delta_time = f64(time.tick_since(game.frame_time_start)) / f64(time.Second)
	game.frame_time_start = time.tick_now()

	if glfw.WindowShouldClose(game.window) do return false
	// if action_is_pressed(.ExitGame) do return false

	glfw.PollEvents()

	im_vk.NewFrame()
	im_glfw.NewFrame()
	im.NewFrame()

	simulate_input()
	update_physics(game.delta_time)
	update_game_state(game.delta_time)
	update_imgui()

	draw()

	return true
}

update_physics :: proc(dt: f64) {
	using px

	scope_stat_time(.Physics)

	scene_simulate_mut(game.phys.scene, f32(dt), nil, nil, 0, true)
	error: u32 = 0
	scene_fetch_results_mut(game.phys.scene, true, &error)
}

update_game_state :: proc(delta_time: f64) {
	scope_stat_time(.GameState)

	camera := get_entity(game.state.camera_id)

	for &ball in get_entities(Ball) {
		update_ball_fixed(&ball)
	}

	update_camera(camera, delta_time)
}

@(export)
game_shutdown :: proc() {
	using px

	px.controller_manager_release_mut(game.phys.controller_manager)
	scene_release_mut(game.phys.scene)
	physics_release_mut(game.phys.physics)
	default_cpu_dispatcher_release_mut(game.phys.dispatcher)
	foundation_release_mut(game.phys.foundation)

	gfx.shutdown()
}
