package main

import "core:fmt"
import "core:mem"
import "core:reflect"

import vk "vendor:vulkan"
import win "core:sys/windows"
import "vendor:cgltf"
import vkr "./renderer"
import glfw "vendor:glfw"
import "core:math"
import "core:math/linalg"
import im "deps:odin-imgui"
import im_glfw "deps:odin-imgui/imgui_impl_glfw"
import im_vk "deps:odin-imgui/imgui_impl_vulkan"

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

	engine()
}

engine :: proc() {
	engine := vkr.VulkanEngine {
		window_extent = {1700, 900},
	}

	init_game_state()

	if !vkr.init(&engine) {
		fmt.println("App could not be initialized.")
	}

	if !glfw.WindowShouldClose(engine.window) {
		update(&engine)
		vkr.render(&engine)

		// Free temp allocations
		free_all(context.temp_allocator)
	}
}

update :: proc(engine: ^vkr.VulkanEngine) {
	update_game_state(engine)
	update_imgui(engine)
}

update_game_state :: proc(engine: ^vkr.VulkanEngine) {
	{
		pitch := linalg.quaternion_angle_axis(game_state.camera.camera_rot.x, [3]f32{1, 0, 0})
		yaw := linalg.quaternion_angle_axis(game_state.camera.camera_rot.y, [3]f32{0, -1, 0})
		game_state.camera.rotation = linalg.mul(yaw, pitch)

		forward := linalg.vector_normalize(linalg.quaternion_mul_vector3(game_state.camera.rotation, [3]f32{0, 0, -1}))
		right := linalg.vector_cross3(forward, [3]f32{0, 1, 0})

		key_w := glfw.GetKey(engine.window, glfw.KEY_W) == glfw.PRESS
		key_a := glfw.GetKey(engine.window, glfw.KEY_A) == glfw.PRESS
		key_s := glfw.GetKey(engine.window, glfw.KEY_S) == glfw.PRESS
		key_d := glfw.GetKey(engine.window, glfw.KEY_D) == glfw.PRESS
		key_space := glfw.GetKey(engine.window, glfw.KEY_SPACE) == glfw.PRESS
		key_space |= glfw.GetKey(engine.window, glfw.KEY_E) == glfw.PRESS
		key_shift := glfw.GetKey(engine.window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS
		key_shift |= glfw.GetKey(engine.window, glfw.KEY_Q) == glfw.PRESS

		if key_w {
			game_state.camera.velocity += forward * 20 * engine.delta_time
		}
		if key_a {
			game_state.camera.velocity += right * -20 * engine.delta_time
		}
		if key_s {
			game_state.camera.velocity += forward * -20 * engine.delta_time
		}
		if key_d {
			game_state.camera.velocity += right * 20 * engine.delta_time
		}
		if key_space {
			game_state.camera.velocity += {0, 1, 0} * 20 * engine.delta_time
		}
		if key_shift {
			game_state.camera.velocity += {0, -1, 0} * 20 * engine.delta_time
		}

		game_state.camera.translation += game_state.camera.velocity * engine.delta_time
		if linalg.length(game_state.camera.velocity) > 0.0 {
			friction: f32 = 0.1
			game_state.camera.velocity = linalg.lerp(game_state.camera.velocity, 0.0, 1-math.pow_f32(friction, engine.delta_time))
		}
	}
}

update_imgui :: proc(engine: ^vkr.VulkanEngine) {
	io := im.GetIO()
	glfw.PollEvents()

	im_vk.NewFrame()
	im_glfw.NewFrame()
	im.NewFrame()

	yaw_delta_a, pitch_delta_a := glfw.GetCursorPos(engine.window)

	yaw_delta := linalg.to_radians((f32(yaw_delta_a) / f32(engine.window_extent.width)) - 0.5) * 100
	pitch_delta := linalg.to_radians((f32(pitch_delta_a) / f32(engine.window_extent.height)) - 0.5) * -50

	wants_rotate_camera := glfw.GetMouseButton(engine.window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS
	if wants_rotate_camera {
		glfw.SetCursorPos(engine.window, f64(engine.window_extent.width) / 2, f64(engine.window_extent.height) / 2)
	}

	if game_state.camera.rotating_camera {
		game_state.camera.camera_rot += {f32(pitch_delta), f32(yaw_delta)}
	}

	if game_state.camera.rotating_camera != wants_rotate_camera {
		if wants_rotate_camera {
			glfw.SetInputMode(engine.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
			glfw.SetInputMode(engine.window, glfw.CURSOR, glfw.RAW_MOUSE_MOTION)
		} else {
			glfw.SetInputMode(engine.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		}
	}

	game_state.camera.rotating_camera = wants_rotate_camera

	if (im.Begin("Camera")) {
		im.InputFloat3("pos", &game_state.camera.translation)
		im.InputFloat2("pitch yaw", &game_state.camera.camera_rot)
		im.InputFloat("fov", cast(^f32)(&game_state.camera.camera_fov_deg))
		items := [3]cstring{"SceneColor", "SceneDepth", "SunShadowDepth"}
		im.ComboChar("view", cast(^i32)(&game_state.camera.view_state), raw_data(&items), len(items))
	}
	im.End()

	if (im.Begin("Environment")) {
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
