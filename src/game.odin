package game

import "core:log"
import "core:fmt"
import "core:math/linalg"
import "core:time"

import glfw "vendor:glfw"
import ma "vendor:miniaudio"

import im "deps:odin-imgui"
import im_glfw "deps:odin-imgui/imgui_impl_glfw"
import im_vk "deps:odin-imgui/imgui_impl_vulkan"
import px "deps:physx-odin"

import "gfx"

//import lpp "deps:odin-livepp"
ENABLE_LIVEPP :: false

start_live_time := time.tick_now()

game: ^Game

main_game :: proc() {
    if !load_generated_assets() {
        fmt.eprintln("Failed to load assets!")
    }

	when ENABLE_LIVEPP {
        local_preferences := lpp.CreateDefaultLocalPreferences()
        project_preferences := lpp.CreateDefaultProjectPreferences()
        project_preferences.exceptionHandler.isEnabled = false

		lpp_agent := lpp.CreateSynchronizedAgentWithPreferencesANSI(&local_preferences, "./deps/odin-livepp/LivePP", &project_preferences)

		// bail out in case the agent is not valid
		if !lpp.IsValidSynchronizedAgent(&lpp_agent) {
			log.error("Failed to initialize LPP agent.")
			return
		}

		// enable Live++ for all loaded modules
		lpp_agent.EnableModule(lpp.GetCurrentModulePath(), .ALL_IMPORT_MODULES, nil, nil)
	}

	glfw.Init()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
	glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
	glfw.SwapInterval(1)

	window := glfw.CreateWindow(1920, 1080, "Vulkan", nil, nil)

	game = new(Game)
	game.config = default_game_config()
	glfw.Init()

	game.window = window

	game.renderer = gfx.init({window = game.window, msaa_samples = ._4, enable_validation_layers = true, enable_logs = true})
	if game.renderer == nil {
		log.error("Graphics could not be initialized.")
        return
	}

	// init_entity_system()
	init_input_system()
	init_sound_system()
	// init_asset_system()

	configure_im()

	g_physx_error_callback := px.create_error_callback(user_error_callback, nil)

	// Physics
	{
		PX_PHYSICS_VERSION_MAJOR :: 5
		PX_PHYSICS_VERSION_MINOR :: 1
		PX_PHYSICS_VERSION_BUGFIX :: 3

		PX_PHYSICS_VERSION :: ((PX_PHYSICS_VERSION_MAJOR << 24) + (PX_PHYSICS_VERSION_MINOR << 16) + (PX_PHYSICS_VERSION_BUGFIX << 8) + 0)

		game.phys.foundation = px.create_foundation(PX_PHYSICS_VERSION, px.get_default_allocator(), g_physx_error_callback)

		assert(game.phys.foundation != nil)

		game.phys.dispatcher = px.default_cpu_dispatcher_create(1, nil, px.DefaultCpuDispatcherWaitForWorkMode.WaitForWork, 0)

		game.phys.physics = px.create_physics_ext(game.phys.foundation)

		assert(px.get_foundation() == game.phys.foundation)
		assert(px.physics_get_foundation_mut(game.phys.physics) == game.phys.foundation)

		callback_info := px.SimulationEventCallbackInfo {
			collision_callback        = collision_callback,
			trigger_callback          = trigger_callback,
			constraint_break_callback = constraint_break_callback,
			wake_sleep_callback       = wake_sleep_callback,
			advance_callback          = advance_callback,
		}

		callback := px.create_simulation_event_callbacks(&callback_info)

		scene_desc := px.scene_desc_new(px.tolerances_scale_new(1.0, 10.0))
		scene_desc.gravity = px.vec3_new_3(0.0, -9.81 * 2, 0.0)
		scene_desc.cpuDispatcher = game.phys.dispatcher
		scene_desc.simulationEventCallback = callback

		px.enable_custom_filter_shader(&scene_desc, collision_filter_shader, 1)

		game.phys.scene = px.physics_create_scene_mut(game.phys.physics, scene_desc)

		game.phys.controller_manager = px.create_controller_manager(game.phys.scene, false)

		px.scene_set_visualization_culling_box_mut(game.phys.scene, px.bounds3_new_1({-50, -50, -50}, {50, 50, 50}))

		// 	// create a ground plane to the scene
		// 	ground_material := physics_create_material_mut(game.phys.physics, 0.5, 0.5, 0.3)
		// 	ground_plane := create_plane(game.phys.physics, plane_new_1(0.0, 1.0, 0.0, 0.0), ground_material)
		// 	scene_add_actor_mut(game.phys.scene, ground_plane, nil)
	}

	// Rendering
	{
		init_game_renderer()
	}

	// Input
	{
		add_action_key_mapping(.Jump, glfw.KEY_SPACE)
		add_action_key_mapping(.Sprint, glfw.KEY_LEFT_SHIFT)
		add_action_key_mapping(.ToggleNoclip, glfw.KEY_V)
		add_action_key_mapping(.LockCamera, glfw.KEY_M)
		add_action_key_mapping(.ShowDebug, glfw.KEY_N)
		add_action_key_mapping(.Fullscreen, glfw.KEY_F10)
		add_action_key_mapping(.ExitGame, glfw.KEY_ESCAPE)

		add_action_mouse_mapping(.Fire, glfw.MOUSE_BUTTON_LEFT)
		add_action_mouse_mapping(.AltFire, glfw.MOUSE_BUTTON_RIGHT)

		add_axis_key_mapping(.MoveForward, glfw.KEY_W, 1.0)
		add_axis_key_mapping(.MoveForward, glfw.KEY_S, -1.0)
		add_axis_key_mapping(.MoveRight, glfw.KEY_D, 1.0)
		add_axis_key_mapping(.MoveRight, glfw.KEY_A, -1.0)

		add_axis_mouse_axis(.LookRight, mouse_x = true)
		add_axis_mouse_axis(.LookUp, mouse_y = true)
	}

	// Scene
	{
		game.render_state.draw_skybox = true

		player := new_entity(Player)
		init_player(player)
		player.translation = {3, 3.7, 5}
		player.camera_rot = {-0.4, -0.6, 0}
		player.camera_fov_deg = 65

		grid_size: f32 = 3.0

		skeleton, anim, ok := load_skel_mesh_from_file(asset_path(.sk_skeltest2))
		assert(ok)
		defer_destroy_gpu_skel_mesh(&gfx.renderer().global_arena, skeleton.buffers)

		// LEAK: Needs asset system.
		skel_ptr := new(Skeleton)
		skel_ptr^ = skeleton

		// LEAK: Needs asset system.
		// anim_ptr := new(SkeletalAnimation)
		// anim_ptr^ = anim
		//
		// for i in 0 ..< grid_size / 2 {
		// 	for j in 0 ..< grid_size * 2 {
		// 		for k in 0 ..< grid_size / 2 {
		// 			ball := new_entity(Ball)
		// 			init_ball(ball, {i * 3, j * 3, k * 3}, {}, skel_ptr, anim_ptr)
		// 		}
		// 	}
		// }

		test_mesh := new_entity(StaticMesh)
		init_static_mesh(test_mesh, .sm_map_test, 0)

		test_mesh2 := new_entity(StaticMesh)
		init_static_mesh(test_mesh2, .sm_materialball2, 2)

		sound_source := new_entity(SoundSource)
		init_sound_source(sound_source, .a_outdoors_birds, true, 0.1, false, 0.5)

		// point_light := new_entity(PointLight)
		// init_point_light(point_light, {0, 4, 2}, {1, 0, 0}, 20, 100)

		game.state = GameState {
			player_id = entity_id_of(player),
			environment = Environment{sun_direction = linalg.normalize(Vec3{12, 15, 10}), sun_color = 2.0, sky_color = 1.0},
		}
	}

	game.frame_time_start = time.tick_now()

    glfw.ShowWindow(window)

	window_open := true
	for window_open {
		scope_stat_time(.Total)

		if glfw.GetWindowAttrib(game.window, glfw.FOCUSED) > 0 {
			ma.engine_set_volume(&game.sound_system.sound_engine, 1.0)
		} else {
			ma.engine_set_volume(&game.sound_system.sound_engine, 0.0)
		}

		game.live_time = f64(time.tick_since(start_live_time)) / f64(time.Second)

		game.delta_time = f64(time.tick_since(game.frame_time_start)) / f64(time.Second)
		game.frame_time_start = time.tick_now()

		dt := game.delta_time

		if glfw.WindowShouldClose(game.window) {
			window_open = false
			break
		}

		glfw.PollEvents()

		if glfw.GetWindowAttrib(game.window, glfw.ICONIFIED) == 0 {
			im_vk.NewFrame()
			im_glfw.NewFrame()
			im.NewFrame()
		}

		simulate_input()

		// Update Game State
		{
			scope_stat_time(.GameState)

			player := get_entity(game.state.player_id)

			for &ball in get_entities(Ball) {
				update_ball_fixed(&ball)
			}

			update_player(player, dt)
		}

		// Update Physics
		{
			scope_stat_time(.Physics)

			px.scene_simulate_mut(game.phys.scene, f32(dt), nil, nil, 0, true)
			error: u32 = 0
			px.scene_fetch_results_mut(game.phys.scene, true, &error)
		}

		if glfw.GetWindowAttrib(game.window, glfw.ICONIFIED) == 0 {
			update_imgui()
			draw()
		}

		if action_just_pressed(.Fullscreen) {
			// 
			game.window_state.is_fullscreen = !game.window_state.is_fullscreen

			monitor := glfw.GetPrimaryMonitor()
			mode := glfw.GetVideoMode(monitor)

			if game.window_state.is_fullscreen {
				x, y := glfw.GetWindowPos(game.window)
				w, h := glfw.GetWindowSize(game.window)

				game.window_state.windowed_pos = {x, y}
				game.window_state.windowed_size = {w, h}

				glfw.SetWindowMonitor(game.window, monitor, 0, 0, mode.width, mode.height, mode.refresh_rate)
			} else {
				glfw.SetWindowMonitor(
					game.window,
					nil,
					game.window_state.windowed_pos.x,
					game.window_state.windowed_pos.y,
					game.window_state.windowed_size.x,
					game.window_state.windowed_size.y,
					mode.refresh_rate,
				)
			}
		}

		free_all(context.temp_allocator)

        when ENABLE_LIVEPP {
            if lpp_agent.WantsReload(.SYNCHRONIZE_WITH_RELOAD) {
                lpp_agent.Reload(.WAIT_UNTIL_CHANGES_ARE_APPLIED)
            }

            if lpp_agent.WantsRestart() {
                // The others don't seem to work. We would need to advance a frame to handle graceful termination,
                // but this function doesn't return until the process is terminated.
                lpp_agent.Restart(.INSTANT_TERMINATION, 0, nil)
            }
        }
	}

	free_all(context.temp_allocator)

	px.controller_manager_release_mut(game.phys.controller_manager)
	px.scene_release_mut(game.phys.scene)
	px.physics_release_mut(game.phys.physics)
	px.default_cpu_dispatcher_release_mut(game.phys.dispatcher)
	px.foundation_release_mut(game.phys.foundation)

	renderer_shutdown()

    when ENABLE_LIVEPP {
        lpp.DestroySynchronizedAgent(&lpp_agent)
    }
}
