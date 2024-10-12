package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:reflect"

import "core:c"
import "core:math"
import "core:math/linalg"
import hlsl "core:math/linalg/hlsl"
import "core:math/rand"
import "core:strings"
import "core:sync"
import win "core:sys/windows"
import "core:time"
import "vendor:cgltf"
import glfw "vendor:glfw"

import gfx "./gfx"

import im "deps:odin-imgui"
import im_glfw "deps:odin-imgui/imgui_impl_glfw"
import im_vk "deps:odin-imgui/imgui_impl_vulkan"

main :: proc() {
	when ODIN_OS == .Windows {
		// Use UTF-8 for console output (fixes emojis/unicode/utf-8 shenanigans)
		win.SetConsoleOutputCP(.UTF8)
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

	init_parallel_for_thread_pool(12)
	defer destroy_parallel_for_thread_pool()

	init_game()

	configure_im()

	game.start_time = time.tick_now()

	game_loop()
}

init_window :: proc(width, height: c.int) -> glfw.WindowHandle {
	glfw.Init()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	return glfw.CreateWindow(i32(width), i32(height), "Vulkan", nil, nil)
}

init_game :: proc() {
	game.window = init_window(1920, 1080)

	if !gfx.init(game.window, {msaa_samples = ._4}) {
		fmt.println("Graphics could not be initialized.")
	}

	init_game_draw()

	camera := new_entity(Camera)
	camera.translation = {-9, 9.5, 14}
	camera.camera_rot = {-0.442, 0.448}
	camera.camera_fov_deg = 45
	camera.view_state = .SceneColor

	player := new_entity(Player)
	player.translation = {0.0, 100.0, 100.0}

	game.state = GameState {
		camera_id = entity_id_of(camera),
		player_id = entity_id_of(player),
		environment = Environment{sun_pos = {12, 15, 10}, sun_target = 0.0, sun_color = 2.0, sky_color = {.4, .35, .55}, bias = 0.001},
	}
}

game_loop :: proc() {
	for !glfw.WindowShouldClose(game.window) {
		start := time.tick_now()

		update()

		start_render := time.tick_now()

		draw()

		game.frame_time_render = f32(time.tick_since(start_render)) / f32(time.Millisecond)

		game.frame_time_total = f32(time.tick_since(start)) / f32(time.Millisecond)
		game.delta_time = f64(time.tick_since(start)) / f64(time.Second)
		game.live_time = f64(time.tick_since(game.start_time)) / f64(time.Second)

		// Free temp allocations
		free_all(context.temp_allocator)
	}
}

update :: proc() {
	update_game_state(game.delta_time)
	update_imgui()
}

update_game_state :: proc(delta_time: f64) {
	start_game_state := time.tick_now()
	player := get_entity(game.state.player_id)
	camera := get_entity(game.state.camera_id)

	update_main_camera(camera, delta_time)

	game.frame_time_game_state = f32(time.tick_since(start_game_state)) / f32(time.Millisecond)
}

update_main_camera :: proc(camera: ^Camera, delta_time: f64) {
	camera := get_entity(game.state.camera_id)
	{
		yaw_delta_a, pitch_delta_a := glfw.GetCursorPos(game.window)

		// TODO: fix references to r_ctx.
		yaw_delta := linalg.to_radians((f32(yaw_delta_a) / f32(gfx.r_ctx.window_extent.width)) - 0.5) * 100
		pitch_delta := linalg.to_radians((f32(pitch_delta_a) / f32(gfx.r_ctx.window_extent.height)) - 0.5) * -50

		wants_rotate_camera := glfw.GetMouseButton(game.window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS
		if wants_rotate_camera {
			// TODO: fix references to r_ctx.
			glfw.SetCursorPos(game.window, f64(gfx.r_ctx.window_extent.width) / 2, f64(gfx.r_ctx.window_extent.height) / 2)
		}

		if camera != nil {
			if camera.rotating_camera {
				camera.camera_rot += {f32(pitch_delta), f32(yaw_delta)}
			}

			if camera.rotating_camera != wants_rotate_camera {
				if wants_rotate_camera {
					glfw.SetInputMode(game.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
					glfw.SetInputMode(game.window, glfw.CURSOR, glfw.RAW_MOUSE_MOTION)
				} else {
					glfw.SetInputMode(game.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
				}
			}

			camera.rotating_camera = wants_rotate_camera
		}
	}

	if camera != nil {
		pitch := linalg.quaternion_angle_axis(camera.camera_rot.x, [3]f32{1, 0, 0})
		yaw := linalg.quaternion_angle_axis(camera.camera_rot.y, [3]f32{0, -1, 0})
		camera.rotation = yaw * pitch

		forward := linalg.vector_normalize(linalg.quaternion_mul_vector3(camera.rotation, [3]f32{0, 0, -1}))
		right := linalg.vector_cross3(forward, [3]f32{0, 1, 0})

		key_w := glfw.GetKey(game.window, glfw.KEY_W) == glfw.PRESS
		key_a := glfw.GetKey(game.window, glfw.KEY_A) == glfw.PRESS
		key_s := glfw.GetKey(game.window, glfw.KEY_S) == glfw.PRESS
		key_d := glfw.GetKey(game.window, glfw.KEY_D) == glfw.PRESS
		key_space := glfw.GetKey(game.window, glfw.KEY_SPACE) == glfw.PRESS
		key_space |= glfw.GetKey(game.window, glfw.KEY_E) == glfw.PRESS
		key_shift := glfw.GetKey(game.window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS
		key_shift |= glfw.GetKey(game.window, glfw.KEY_Q) == glfw.PRESS

		accelleration: f32 = 120

		if key_w {
			camera.velocity += forward * accelleration * f32(delta_time)
		}
		if key_a {
			camera.velocity += right * -accelleration * f32(delta_time)
		}
		if key_s {
			camera.velocity += forward * -accelleration * f32(delta_time)
		}
		if key_d {
			camera.velocity += right * accelleration * f32(delta_time)
		}
		if key_space {
			camera.velocity += {0, 1, 0} * accelleration * f32(delta_time)
		}
		if key_shift {
			camera.velocity += {0, -1, 0} * accelleration * f32(delta_time)
		}

		camera.translation += camera.velocity * f32(delta_time)
		if linalg.length(camera.velocity) > 0.0 {
			friction: f32 = 0.0005
			camera.velocity = linalg.lerp(camera.velocity, 0.0, 1 - math.pow_f32(friction, f32(delta_time)))
		}
	}
}

update_imgui :: proc() {
	io := im.GetIO()
	glfw.PollEvents()

	im_vk.NewFrame()
	im_glfw.NewFrame()
	im.NewFrame()

	if im.Begin("Entities") {
		if im.CollapsingHeader("Raw Entities") {
			clipper: im.ListClipper
			im.ListClipper_Begin(&clipper, i32(NUM_ENTITIES))

			for im.ListClipper_Step(&clipper) {
				for i in clipper.DisplayStart ..< clipper.DisplayEnd {
					entity := ENTITIES[i]
					if entity.id.live {
						im.Text("entity")
						im.BulletText("id %d", entity.id.index)
						im.BulletText("gen %d", entity.id.generation)
					} else {
						im.Text("deleted entity")
					}
				}
			}
		}

		imgui_draw_type :: proc(t: typeid, data: rawptr = nil) {
			info_base := type_info_of(t)

			info_named: runtime.Type_Info_Named
			info_struct: runtime.Type_Info_Struct

			#partial switch info in info_base.variant {
			case runtime.Type_Info_Pointer:
				info_ptr := info_base.variant.(runtime.Type_Info_Pointer)
				info_named = info_ptr.elem.variant.(runtime.Type_Info_Named)
				info_struct = info_named.base.variant.(runtime.Type_Info_Struct)
			case runtime.Type_Info_Named:
				info_named = info_base.variant.(runtime.Type_Info_Named)
				info_struct = info_named.base.variant.(runtime.Type_Info_Struct)
			case:
				return // we don't support this case.
			}

			display_string: cstring

			if data == nil {
				display_string = strings.clone_to_cstring(info_named.name, context.temp_allocator)
			} else {
				entity := (^Entity)(data)
				display_string = fmt.ctprintf("%s %p", info_named.name, data)
			}

			im.Text(display_string)
			for i in 0 ..< info_struct.field_count {
				name := info_struct.names[i]
				ty := info_struct.types[i]
				offset := info_struct.offsets[i]
				is_using := info_struct.usings[i]

				if data == nil {
					im.Text(strings.clone_to_cstring(name, context.temp_allocator))
				} else {
					data_ptr := (rawptr)(mem.ptr_offset((^u8)(data), offset))

					// #partial switch info in ty.variant {
					// 	case runtime.Type_Info_Pointer, runtime.Type_Info_Struct:
					// 		imgui_draw_type(ty.id, data_ptr)
					// 		continue
					// }

					data_typed := any {
						id   = ty.id,
						data = data_ptr,
					}

					im.Text(fmt.ctprintf("   %s %v %p @ %d = %v", name, ty, data_ptr, offset, data_typed))
				}
			}
			im.Text("")
		}

		for key, subtype_ptr in SUBTYPE_STORAGE {
			storage_raw := cast(^RawSparseSet)subtype_ptr
			size_t := type_info_of(key).size

			if im.TreeNode(
				fmt.ctprintf("%s Entities (num: %d)", type_info_of(key).variant.(runtime.Type_Info_Named).name, storage_raw.dense.len),
			) {
				clipper: im.ListClipper
				im.ListClipper_Begin(&clipper, i32(storage_raw.dense.len))

				for im.ListClipper_Step(&clipper) {
					for i in clipper.DisplayStart ..< clipper.DisplayEnd {
						data_ptr := (rawptr)(mem.ptr_offset((^u8)(storage_raw.dense.data), int(i) * size_t))
						imgui_draw_type(key, data_ptr)
					}
				}
				im.TreePop()
			}
		}
	}
	im.End()

	camera := get_entity(game.state.camera_id)

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
		im.InputFloat3("pos", cast(^[3]f32)(&game.state.environment.sun_pos))
		im.InputFloat3("target", cast(^[3]f32)(&game.state.environment.sun_target))
		im.ColorEdit3("sun_color", cast(^[3]f32)(&game.state.environment.sun_color))
		im.ColorEdit3("sky_color", cast(^[3]f32)(&game.state.environment.sky_color))
		im.InputFloat("bias", cast(^f32)(&game.state.environment.bias))
	}
	im.End()

	if (im.Begin("Stats")) {
		im.Text("total frametime %f ms", game.frame_time_total)
		im.BulletText("game %f ms", game.frame_time_game_state)
		im.BulletText("physics %f ms", game.frame_time_physics)
		im.BulletText("render %f ms", game.frame_time_render)
	}
	im.End()

	if (im.Begin("Skeletal Animation")) {
		im.SliderFloat("sample time", &game.sample_time, 0.0, 5.0)
		im.SliderFloat("sample rate", &game.skel_animator.rate, 0.1, 10.0)

		im.Checkbox("Use game time", &game.use_game_time)
		if game.use_game_time {
			game.sample_time = f32(game.live_time)
		}

		gfx.sample_animation(&game.skel_animator, game.sample_time)

		im.Text("sample time %f s", game.sample_time)
		for joint, i in game.skel_animator.calc_joints {
			if im.CollapsingHeader(fmt.ctprint("Joint", i)) {
				im.InputFloat4("", &[4]f32{joint[0, 0], joint[1, 0], joint[2, 0], joint[3, 0]})
				im.InputFloat4("", &[4]f32{joint[0, 1], joint[1, 1], joint[2, 1], joint[3, 1]})
				im.InputFloat4("", &[4]f32{joint[0, 2], joint[1, 2], joint[2, 2], joint[3, 2]})
				im.InputFloat4("", &[4]f32{joint[0, 3], joint[1, 3], joint[2, 3], joint[3, 3]})
			}
		}
	}
	im.End()
}


@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
