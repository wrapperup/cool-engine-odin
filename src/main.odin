package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:reflect"

import "core:math"
import "core:math/linalg"
import "core:strings"
import win "core:sys/windows"
import im "deps:odin-imgui"
import im_glfw "deps:odin-imgui/imgui_impl_glfw"
import im_vk "deps:odin-imgui/imgui_impl_vulkan"
import "vendor:cgltf"
import glfw "vendor:glfw"
import vk "vendor:vulkan"

main :: proc() {
	when ODIN_OS == .Windows {
		// Use UTF-8 for console output (fixes emojis/unicode/utf-8 shenanigans)
		win.SetConsoleOutputCP(win.CP_UTF8)
	}
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	run_engine()
}

run_engine :: proc() {
	engine := VulkanEngine {
		window_extent = {1700, 900},
	}

	init_game_state()

	if !init(&engine) {
		fmt.println("App could not be initialized.")
	}

	for !glfw.WindowShouldClose(engine.window) {
		update(&engine)
		render(&engine)

		// Free temp allocations
		free_all(context.temp_allocator)
	}

	free_game_state()
}

update :: proc(engine: ^VulkanEngine) {
	update_game_state(engine, engine.delta_time)
	update_imgui(engine)
}

init_game_state :: proc() {
	camera_id, camera := new_entity_with_typed_id(Camera)
	player := new_entity(Player)
	camera.translation = {-9, 9.5, 14}
	camera.camera_rot = {-0.442, 0.448}
	camera.camera_fov_deg = 45
	camera.view_state = .SceneColor

	game_state = GameState {
		camera_id = camera_id,
		environment = Environment {
			sun_pos = {12, 15, 10},
			sun_target = 0.0,
			sun_color = 1.0,
			sky_color = {.4, .35, .55},
			bias = 0.001,
		},
	}
}

free_game_state :: proc() {
	clear_dynamic_array(&entities)
}

update_game_state :: proc(engine: ^VulkanEngine, dt: f64) {
	camera := get_entity(game_state.camera_id)

	{
		yaw_delta_a, pitch_delta_a := glfw.GetCursorPos(engine.window)

		yaw_delta := linalg.to_radians((f32(yaw_delta_a) / f32(engine.window_extent.width)) - 0.5) * 100
		pitch_delta := linalg.to_radians((f32(pitch_delta_a) / f32(engine.window_extent.height)) - 0.5) * -50

		wants_rotate_camera := glfw.GetMouseButton(engine.window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS
		if wants_rotate_camera {
			glfw.SetCursorPos(engine.window, f64(engine.window_extent.width) / 2, f64(engine.window_extent.height) / 2)
		}

		if camera != nil {
			if camera.rotating_camera {
				camera.camera_rot += {f32(pitch_delta), f32(yaw_delta)}
			}

			if camera.rotating_camera != wants_rotate_camera {
				if wants_rotate_camera {
					glfw.SetInputMode(engine.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
					glfw.SetInputMode(engine.window, glfw.CURSOR, glfw.RAW_MOUSE_MOTION)
				} else {
					glfw.SetInputMode(engine.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
				}
			}

			camera.rotating_camera = wants_rotate_camera
		}
	}

	if camera != nil {
		pitch := linalg.quaternion_angle_axis(camera.camera_rot.x, [3]f32{1, 0, 0})
		yaw := linalg.quaternion_angle_axis(camera.camera_rot.y, [3]f32{0, -1, 0})
		camera.rotation = linalg.mul(yaw, pitch)

		forward := linalg.vector_normalize(linalg.quaternion_mul_vector3(camera.rotation, [3]f32{0, 0, -1}))
		right := linalg.vector_cross3(forward, [3]f32{0, 1, 0})

		key_w := glfw.GetKey(engine.window, glfw.KEY_W) == glfw.PRESS
		key_a := glfw.GetKey(engine.window, glfw.KEY_A) == glfw.PRESS
		key_s := glfw.GetKey(engine.window, glfw.KEY_S) == glfw.PRESS
		key_d := glfw.GetKey(engine.window, glfw.KEY_D) == glfw.PRESS
		key_space := glfw.GetKey(engine.window, glfw.KEY_SPACE) == glfw.PRESS
		key_space |= glfw.GetKey(engine.window, glfw.KEY_E) == glfw.PRESS
		key_shift := glfw.GetKey(engine.window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS
		key_shift |= glfw.GetKey(engine.window, glfw.KEY_Q) == glfw.PRESS

		accelleration: f32 = 120

		if key_w {
			camera.velocity += forward * accelleration * f32(dt)
		}
		if key_a {
			camera.velocity += right * -accelleration * f32(dt)
		}
		if key_s {
			camera.velocity += forward * -accelleration * f32(dt)
		}
		if key_d {
			camera.velocity += right * accelleration * f32(dt)
		}
		if key_space {
			camera.velocity += {0, 1, 0} * accelleration * f32(dt)
		}
		if key_shift {
			camera.velocity += {0, -1, 0} * accelleration * f32(dt)
		}

		camera.translation += camera.velocity * f32(dt)
		if linalg.length(camera.velocity) > 0.0 {
			friction: f32 = 0.0005
			camera.velocity = linalg.lerp(camera.velocity, 0.0, 1 - math.pow_f32(friction, f32(dt)))
		}
	}
}

update_players :: proc() {

}

update_imgui :: proc(engine: ^VulkanEngine) {
	io := im.GetIO()
	glfw.PollEvents()

	im_vk.NewFrame()
	im_glfw.NewFrame()
	im.NewFrame()

	if im.Begin("Entities") {
		if im.Button("create player entity") {
			new_entity(Player)
		}
		if im.Button("create camera entity") {
			new_entity(Camera)
		}
		if im.Button("delete last entity") {
			#reverse for &entity_gen_ptr, i in entities {
				if entity_gen_ptr.entity_ptr != nil {
					remove_entity(entities[i].entity_ptr.entity_id)
					break
				}
			}
		}
		for &entity_gen_ptr in &entities {
			if entity_gen_ptr.entity_ptr != nil {
				im.Text("entity")
				im.BulletText("id %d", entity_gen_ptr.entity_ptr.entity_id.index)
				im.BulletText("gen %d", entity_gen_ptr.entity_ptr.entity_id.generation)
			} else {
				im.Text("deleted entity")
			}
		}
	}
	im.End()

	camera := get_entity(game_state.camera_id)

	if camera != nil {
		if im.Begin("Camera") {
			im.InputFloat3("pos", &camera.translation)
			im.InputFloat2("pitch yaw", &camera.camera_rot)
			im.InputFloat("fov", cast(^f32)(&camera.camera_fov_deg))
			items := [3]cstring{"SceneColor", "SceneDepth", "SunShadowDepth"}
			im.ComboChar("view", cast(^i32)(&camera.view_state), raw_data(&items), len(items))
		}
		im.End()
	}

	if im.Begin("Environment") {
		im.InputFloat3("pos", cast(^[3]f32)(&game_state.environment.sun_pos))
		im.InputFloat3("target", cast(^[3]f32)(&game_state.environment.sun_target))
		im.InputFloat3("sun_color", cast(^[3]f32)(&game_state.environment.sun_color))
		im.InputFloat3("sky_color", cast(^[3]f32)(&game_state.environment.sky_color))
		im.InputFloat("bias", cast(^f32)(&game_state.environment.bias))
	}
	im.End()

	if (im.Begin("Stats")) {
		im.Text("frametime %f ms", engine.frame_time)
		im.Text("tri count %d", engine.tri_count)
	}
	im.End()
}


@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
