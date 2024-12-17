package game

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "vendor:glfw"

import px "deps:physx-odin"

import "gfx"

Move_Mode :: enum {
	Ground,
	Noclip,
}

Player :: struct {
	using entity:               ^Entity,
	//
	move_mode:                  Move_Mode,
	controller:                 ^px.Controller,
	camera_rot:                 Vec3,
	camera_fov_deg:             f32,
	ground_contact_normals:     [dynamic]Vec3,
	fire_time:                  f64,
	momentum:                   f32,
	is_grounded_last_frame:     bool,
	footstep_distance_traveled: f32,
	footstep_time:              f64,
	footstep:                   u32,
	camera_shake_time:          f64,
}

on_shape_hit_callback :: proc "c" (#by_ptr hit: px.ControllerShapeHit) {
	context = runtime.default_context()

	id := entity_id_from_rawptr(px.controller_get_user_data(hit.controller))

	if player := get_entity_subtype(Player, id); player != nil {
		normal := transmute(Vec3)(hit.worldNormal)

		append(&player.ground_contact_normals, normal)
	}
}

on_controller_hit_callback :: proc "c" (#by_ptr hit: px.ControllersHit) {
	context = runtime.default_context()
}

on_obstacle_hit_callback :: proc "c" (#by_ptr hit: px.ControllerObstacleHit) {
	context = runtime.default_context()
}

init_player :: proc(player: ^Player) {
	material := px.physics_create_material_mut(game.phys.physics, 0.9, 0.5, 0.1)

	desc := px.capsule_controller_desc_new_alloc()
	desc.height = 2.0
	desc.radius = 1.0
	desc.maxJumpHeight = 2.0
	desc.slopeLimit = 0.3
	desc.stepOffset = 0.3
	desc.material = material
	desc.nonWalkableMode = .PreventClimbing
	desc.reportCallback = px.create_user_controller_hit_report(on_shape_hit_callback, on_controller_hit_callback, on_obstacle_hit_callback)
	desc.climbingMode = .Constrained
	desc.contactOffset = 0.1

	player.controller = px.controller_manager_create_controller_mut(game.phys.controller_manager, desc)
	px.controller_set_user_data_mut(player.controller, entity_id_to_rawptr(player.id))
	px.controller_set_position_mut(player.controller, {0.0, 10.0, 0.0})
	assert(player.controller != nil)
}

update_player :: proc(player: ^Player, dt: f64) {

	filter_data := px.filter_data_new_2(get_words_from_filter({}))
	filters := px.controller_filters_new(&filter_data, nil, nil)

	collision_flags := px.controller_move_mut(
		player.controller,
		transmute(px.Vec3)((player.velocity * f32(dt)) - {0, player.is_grounded_last_frame ? 0.05 : 0, 0}),
		0.001,
		f32(dt),
		filters,
		nil,
	)

	// Look scheme
	yaw_delta: f32
	pitch_delta: f32

	mouse_x := axis_get_value(.LookRight)
	mouse_y := axis_get_value(.LookUp)

	if action_just_pressed(.LockCamera) {
		toggle_lock_mouse()
	}

	yaw_delta = linalg.to_radians(f32(mouse_x)) * 0.025
	pitch_delta = linalg.to_radians(f32(mouse_y)) * -0.025

	player.camera_rot += {f32(pitch_delta), f32(yaw_delta), 0}
	player.camera_rot.x = math.clamp(player.camera_rot.x, -math.PI / 2, math.PI / 2)
	player.camera_rot.y = math.wrap(player.camera_rot.y, math.PI * 2)

	pitch := linalg.quaternion_angle_axis(player.camera_rot.x, Vec3{1, 0, 0})
	yaw := linalg.quaternion_angle_axis(player.camera_rot.y, Vec3{0, -1, 0})

	look := yaw * pitch

	look_forward := linalg.quaternion_mul_vector3(player.rotation, Vec3{0, 0, -1})
	forward := linalg.quaternion_mul_vector3(yaw, Vec3{0, 0, -1})
	right := linalg.vector_cross3(forward, Vec3{0, 1, 0})

	tilt_angle := math.atan(linalg.dot(player.velocity / 100, right)) / 5
	player.camera_rot.z = linalg.lerp(player.camera_rot.z, tilt_angle, 20.0 * f32(dt))
	tilt := linalg.quaternion_angle_axis(player.camera_rot.z, Vec3{0, 0, -1})

	// General Movement

	player.rotation = look * tilt

	f, r := axis_get_2d_normalized(.MoveForward, .MoveRight)
	move_forward, move_right := cast(f32)f, cast(f32)r

	move_direction := move_forward * forward + move_right * right
	move_direction_n := linalg.normalize0(move_forward * forward + move_right * right)

	if action_just_pressed(.ToggleNoclip) {
		player.move_mode += Move_Mode(1)
		player.move_mode = Move_Mode(int(player.move_mode) % len(Move_Mode))
	}

	set_listener_position(player.translation, look_forward)

	switch player.move_mode {
	case .Ground:
		is_sliding := false
		is_grounded := false

		acceleration: Vec3

		for normal in player.ground_contact_normals {
			slope_angle := linalg.vector_angle_between(normal, Vec3{0, 1, 0})
			is_grounded = is_grounded || slope_angle < math.PI / 4
			is_sliding = !is_grounded

			if is_grounded || is_sliding {
				test_normal := normal
				new_velocity := linalg.normalize(test_normal) * linalg.max((linalg.dot(-test_normal, player.velocity * 1)), 0)

				if is_grounded {
					player.velocity.y += new_velocity.y
				} else {
					player.velocity += new_velocity
				}
			}
		}

		pos := px.controller_get_position(player.controller)
		last_player_translation := player.translation
		player.translation = {f32(pos.x), f32(pos.y), f32(pos.z)}

		player.fire_time += dt

		max_ground_acceleration: f32 = 50
		max_air_acceleration: f32 = 15
		max_braking_acceleration: f32 = 80

		max_ground_speed: f32 = 10
		max_air_speed: f32 = 10

		if action_is_pressed(.Sprint) {
			max_ground_speed = 15
		}

		// Returns the change in acceleration to apply to the player's current acceleration.
		apply_acceleration :: proc(
			requested_dir: Vec3,
			max_speed: f32,
			max_acceleration: f32,
			current_velocity: Vec3,
			has_traction: bool,
			dt: f64,
		) -> Vec3 {
			current_speed := linalg.dot(current_velocity, requested_dir)
			add_speed := max_speed - current_speed

			if add_speed < 0 && !has_traction {
				return 0
			}

			when false {
				// Quake
				acceleration_change := (max_acceleration * max_speed * f32(dt)) * requested_dir
			} else {
				// Unreal
				acceleration_change := ((max_speed * requested_dir) - current_velocity) / f32(dt)
				acceleration_change = linalg.clamp_length(acceleration_change, max_acceleration)
			}

			return acceleration_change
		}

		if linalg.length(move_direction) > 0.01 {
			max_acceleration := is_grounded ? max_ground_acceleration : max_air_acceleration
			max_speed := is_grounded ? max_ground_speed : max_air_speed
			acceleration.xz += apply_acceleration(move_direction_n, max_speed, max_acceleration, player.velocity, is_grounded, dt).xz
		} else if is_grounded && linalg.length(player.velocity.xz) >= (10 * f32(dt)) {
			acceleration.xz +=
				apply_acceleration(-linalg.normalize0(player.velocity), 10, max_braking_acceleration, player.velocity, is_grounded, dt).xz
		} else if is_grounded && linalg.length(player.velocity.xz) < (10 * f32(dt)) {
			acceleration.xz = 0
			player.velocity.xz = 0
		}

		player.velocity += {0, -70, 0} * f32(dt)

		if action_just_pressed(.Fire) {
			play_sound_3d(fmt.ctprintf("assets/audio/footsteps/step%v.wav", player.footstep + 1), player.translation)
			player.fire_time = 0
			player.velocity.xz = move_direction_n.xz * 15
			player.velocity += {0, 1, 0} * 10
			// ball := new_entity(Ball)
			// init_ball(ball, player.translation + look_forward * 2 - {0, 1.5, 0}, player.velocity + look_forward * 100)
		}

		clear(&player.ground_contact_normals)

		player.velocity += acceleration * f32(dt)
		player.is_grounded_last_frame = is_grounded && !is_sliding

		if action_is_pressed(.Jump) && is_grounded {
			player.velocity.y = 20
			player.is_grounded_last_frame = false
		}

		if is_grounded {
			if player.footstep_distance_traveled > 3.5 && player.footstep_time > 0.15 {
				player.footstep_distance_traveled = 0
				player.footstep_time = 0

				play_sound(fmt.ctprintf("assets/audio/footsteps/step%v.wav", player.footstep + 1))
				player.footstep += 1
				player.footstep = player.footstep % 20
			}

			player.footstep_distance_traveled += linalg.length(last_player_translation.xz - player.translation.xz)
		} else {
			player.footstep_distance_traveled = 2
		}

		player.footstep_time += dt

	case .Noclip:
		max_noclip_speed: f32 = 50

		player.velocity = move_direction_n * max_noclip_speed

		if action_is_pressed(.Jump) {
			player.velocity.y = max_noclip_speed
		}
		if action_is_pressed(.Sprint) {
			player.velocity.y = -max_noclip_speed
		}

		player.translation += player.velocity * f32(dt)

		// Force capsule to move.
		px.controller_set_position_mut(player.controller, transmute(px.ExtendedVec3)linalg.array_cast(player.translation, f64))
	}
}

// update_main_player :: proc(player: ^Player, delta_time: f64) {
// 	player := get_entity(game.state.player_id)
// 	{
// 		yaw_delta: f32
// 		pitch_delta: f32
//
// 		wants_rotate_player := glfw.GetMouseButton(game.window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS
// 		// wants_rotate_player := true
//
// 		mouse_x, mouse_y := glfw.GetCursorPos(game.window)
//
// 		if wants_rotate_player {
// 			glfw.SetCursorPos(game.window, f64(game.window_extent.x) / 2, f64(game.window_extent.y) / 2)
// 		}
//
// 		if player.rotating_player {
// 			glfw.SetInputMode(game.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
// 			glfw.SetInputMode(game.window, glfw.CURSOR, glfw.RAW_MOUSE_MOTION)
// 		} else {
// 			glfw.SetInputMode(game.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
// 		}
//
// 		if player.rotating_player && wants_rotate_player {
// 			center := game.window_extent / 2.0
//
// 			mouse_x -= f64(center.x)
// 			mouse_y -= f64(center.y)
//
// 			yaw_delta = linalg.to_radians(f32(mouse_x)) * 0.1
// 			pitch_delta = linalg.to_radians(f32(mouse_y)) * -0.1
//
// 			player.player_rot += {f32(pitch_delta), f32(yaw_delta)}
// 		}
//
// 		player.rotating_player = wants_rotate_player
// 	}
//
// 	if player != nil {
// 		pitch := linalg.quaternion_angle_axis(player.player_rot.x, Vec3{1, 0, 0})
// 		yaw := linalg.quaternion_angle_axis(player.player_rot.y, Vec3{0, -1, 0})
// 		player.rotation = yaw * pitch
//
// 		forward := linalg.quaternion_mul_vector3(player.rotation, Vec3{0, 0, -1})
// 		right := linalg.vector_cross3(forward, Vec3{0, 1, 0})
//
// 		key_w := glfw.GetKey(game.window, glfw.KEY_W) == glfw.PRESS
// 		key_a := glfw.GetKey(game.window, glfw.KEY_A) == glfw.PRESS
// 		key_s := glfw.GetKey(game.window, glfw.KEY_S) == glfw.PRESS
// 		key_d := glfw.GetKey(game.window, glfw.KEY_D) == glfw.PRESS
// 		key_space := glfw.GetKey(game.window, glfw.KEY_SPACE) == glfw.PRESS
// 		key_space |= glfw.GetKey(game.window, glfw.KEY_E) == glfw.PRESS
// 		key_shift := glfw.GetKey(game.window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS
// 		key_shift |= glfw.GetKey(game.window, glfw.KEY_Q) == glfw.PRESS
//
// 		shoot_ray := glfw.GetMouseButton(game.window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS
//
// 		if shoot_ray {
// 			hit, ok := query_raycast_single(player.translation, forward, 50, {.Dynamic, .Static}, true)
// 			if ok {
// 				if ball := get_entity(Ball, entity_id_from_rawptr(hit.actor.userData)); ball != nil {
// 					px.rigid_body_add_force_mut(ball.rigid, transmute(px.Vec3)(transmute(Vec3)hit.normal * -1 * 10), .Impulse, true)
// 				}
// 			}
// 		}
//
// 		accelleration: f32 = 120
//
// 		if key_w {
// 			player.velocity += forward * accelleration * f32(delta_time)
// 		}
// 		if key_a {
// 			player.velocity += right * -accelleration * f32(delta_time)
// 		}
// 		if key_s {
// 			player.velocity += forward * -accelleration * f32(delta_time)
// 		}
// 		if key_d {
// 			player.velocity += right * accelleration * f32(delta_time)
// 		}
// 		if key_space {
// 			player.velocity += {0, 1, 0} * accelleration * f32(delta_time)
// 		}
// 		if key_shift {
// 			player.velocity += {0, -1, 0} * accelleration * f32(delta_time)
// 		}
//
// 		player.translation += player.velocity * f32(delta_time)
// 		if linalg.length(player.velocity) > 0.0 {
// 			friction: f32 = 0.0005
// 			player.velocity = linalg.lerp(player.velocity, 0.0, 1 - math.pow_f32(friction, f32(delta_time)))
// 		}
// 	}
// }

get_view_matrix :: proc(player: ^Player) -> matrix[4, 4]f32 {
	aspect_ratio := f32(game.window_extent.x) / f32(game.window_extent.y)

	translation := linalg.matrix4_translate(player != nil ? player.translation : {})
	rotation := linalg.matrix4_from_quaternion(player != nil ? player.rotation : {})

	return linalg.inverse(linalg.mul(translation, rotation))
}

get_projection_matrix :: proc(player: ^Player) -> matrix[4, 4]f32 {
	aspect_ratio := f32(game.window_extent.x) / f32(game.window_extent.y)

	projection_matrix := gfx.matrix4_infinite_perspective_z0_f32(
		linalg.to_radians(player != nil ? player.camera_fov_deg : 0),
		aspect_ratio,
		0.1,
	)
	projection_matrix[1][1] *= -1.0

	return projection_matrix
}

world_space_to_clip_space :: proc(view_projection: matrix[4, 4]f32, vec: Vec3) -> ([2]f32, bool) {
	vec_p := view_projection * [4]f32{vec.x, vec.y, vec.z, 1.0}
	clip_vec := vec_p.xyz / vec_p.w

	ok := true

	// TODO: uhh.... is there a better way?
	if clip_vec.x > 1 do ok = false
	if clip_vec.y > 1 do ok = false
	if clip_vec.z > 1 do ok = false
	if clip_vec.x < -1 do ok = false
	if clip_vec.y < -1 do ok = false
	if clip_vec.z < -1 do ok = false

	return (clip_vec.xy * 0.5 + 0.5) * [2]f32{f32(game.window_extent.x), f32(game.window_extent.y)}, ok
}
