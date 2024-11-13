package game

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "vendor:glfw"

import px "deps:physx-odin"

import "gfx"

Camera :: struct {
	using entity:           ^Entity,
	//
	controller:             ^px.Controller,
	camera_rot:             [3]f32,
	camera_fov_deg:         f32,
	ground_contact_normals: [dynamic][3]f32,
	fire_time:              f64,
	momentum:               f32,
	is_grounded_last_frame: bool,
}

on_shape_hit_callback :: proc "c" (#by_ptr hit: px.ControllerShapeHit) {
	context = runtime.default_context()

	id := entity_id_from_rawptr(px.controller_get_user_data(hit.controller))

	if camera := get_entity_subtype(Camera, id); camera != nil {
		normal := transmute([3]f32)(hit.worldNormal)

		append(&camera.ground_contact_normals, normal)
	}
}

on_controller_hit_callback :: proc "c" (#by_ptr hit: px.ControllersHit) {
	context = runtime.default_context()
}

on_obstacle_hit_callback :: proc "c" (#by_ptr hit: px.ControllerObstacleHit) {
	context = runtime.default_context()
}

init_camera :: proc(camera: ^Camera) {
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

	camera.controller = px.controller_manager_create_controller_mut(game.phys.controller_manager, desc)
	px.controller_set_user_data_mut(camera.controller, entity_id_to_rawptr(camera.id))
	px.controller_set_position_mut(camera.controller, {0.0, 10.0, 0.0})
	assert(camera.controller != nil)
}

update_camera :: proc(camera: ^Camera, delta_time: f64) {
	filter_data := px.filter_data_new_2(get_words_from_filter({}))
	filters := px.controller_filters_new(&filter_data, nil, nil)

	collision_flags := px.controller_move_mut(
		camera.controller,
		transmute(px.Vec3)((camera.velocity * f32(delta_time)) - {0, 0.01, 0}),
		0.001,
		f32(delta_time),
		filters,
		nil,
	)

	{
		yaw_delta: f32
		pitch_delta: f32

		mouse_x := axis_get_value(.LookRight)
		mouse_y := axis_get_value(.LookUp)

		if action_just_pressed(.LockCamera) {
			toggle_lock_mouse()
		}

		yaw_delta = linalg.to_radians(f32(mouse_x)) * 0.025
		pitch_delta = linalg.to_radians(f32(mouse_y)) * -0.025

		camera.camera_rot += {f32(pitch_delta), f32(yaw_delta), 0}
	}

	pitch := linalg.quaternion_angle_axis(camera.camera_rot.x, [3]f32{1, 0, 0})
	yaw := linalg.quaternion_angle_axis(camera.camera_rot.y, [3]f32{0, -1, 0})

	look := yaw * pitch

	look_forward := linalg.quaternion_mul_vector3(camera.rotation, [3]f32{0, 0, -1})
	forward := linalg.quaternion_mul_vector3(yaw, [3]f32{0, 0, -1})
	right := linalg.vector_cross3(forward, [3]f32{0, 1, 0})

	tilt_angle := math.atan(linalg.dot(camera.velocity / 100, right)) / 6
	camera.camera_rot.z = linalg.lerp(camera.camera_rot.z, tilt_angle, 20.0 * f32(delta_time))
	tilt := linalg.quaternion_angle_axis(camera.camera_rot.z, [3]f32{0, 0, -1})

	camera.rotation = look * tilt

	is_sliding := false
	is_grounded := false

	sum_normals: [3]f32

	acceleration: [3]f32

	for normal in camera.ground_contact_normals {
		slope_angle := linalg.vector_angle_between(normal, [3]f32{0, 1, 0})
		is_grounded = slope_angle < 0.5
		is_sliding = !is_grounded

		if is_grounded || is_sliding {
			test_normal := normal
			new_velocity := linalg.normalize(test_normal) * linalg.max((linalg.dot(-test_normal, camera.velocity * 1)), 0)

			if is_grounded {
				camera.velocity.y += new_velocity.y
			} else {
				camera.velocity += new_velocity
			}
		}
	}

	pos := px.controller_get_position(camera.controller)
	camera.translation = {f32(pos.x), f32(pos.y), f32(pos.z)}

	// camera.velocity += {0, -0.5, 0} * f32(delta_time)

	camera.fire_time += delta_time

	max_move_acceleration: f32 = 50
	max_air_acceleration: f32 = 20
	braking_acceleration: f32 = 75

	momentum_speed: f32 = 5
	max_speed: f32 = 10

	f, r := axis_get_2d_normalized(.MoveForward, .MoveRight)
	move_forward, move_right := cast(f32)f, cast(f32)r

	move_direction := move_forward * forward + move_right * right
	move_direction_n := linalg.normalize0(move_forward * forward + move_right * right)
	// move_direction_n := linalg.normalize0(move_right * forward + -move_forward * right)


	clamp_to_length :: proc(v: [3]$T, max_length: T) -> [3]T {
		if (max_length < 0.001) {
			return 0
		}

		v_sq := linalg.length2(v)
		if (v_sq > max_length * max_length) {
			scale := max_length * linalg.inverse_sqrt(v_sq)
			return v * scale
		}

		return v
	}

	if linalg.length(move_direction) > 0.01 {
		y := acceleration.y
		current_velocity := camera.velocity
		current_velocity.y = 0
		requested_velocity := move_direction_n * max_speed
		requested_speed := linalg.length(requested_velocity)

		max_acceleration := is_grounded ? max_move_acceleration : max_air_acceleration

		new_acceleration := ((requested_velocity - current_velocity) / f32(delta_time))
		new_acceleration = clamp_to_length(new_acceleration, max_acceleration)

		acceleration += new_acceleration
		acceleration.y = y
	} else if is_grounded {
		y := acceleration.y
		current_velocity := camera.velocity
		current_velocity.y = 0
		requested_velocity: [3]f32 = 0
		requested_speed := linalg.length(requested_velocity)

		max_acceleration := braking_acceleration

		new_acceleration := ((requested_velocity - current_velocity) / f32(delta_time))
		new_acceleration = clamp_to_length(new_acceleration, max_acceleration)

		acceleration += new_acceleration
		acceleration.y = y
	}

	camera.velocity += {0, -70, 0} * f32(delta_time)

	if action_is_pressed(.Jump) && is_grounded {
		camera.velocity.y = 30
	}

	if action_is_pressed(.Fire) && camera.fire_time > 0.05 {
		camera.fire_time = 0
		// ball := new_entity(Ball)
		// init_ball(ball, camera.translation + look_forward * 2 - {0, 1.5, 0}, camera.velocity + look_forward * 100)
	}

	clear(&camera.ground_contact_normals)

	camera.velocity += acceleration * f32(delta_time)
	camera.is_grounded_last_frame = is_grounded && !is_sliding
}

// update_main_camera :: proc(camera: ^Camera, delta_time: f64) {
// 	camera := get_entity(game.state.camera_id)
// 	{
// 		yaw_delta: f32
// 		pitch_delta: f32
//
// 		wants_rotate_camera := glfw.GetMouseButton(game.window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS
// 		// wants_rotate_camera := true
//
// 		mouse_x, mouse_y := glfw.GetCursorPos(game.window)
//
// 		if wants_rotate_camera {
// 			glfw.SetCursorPos(game.window, f64(game.window_extent.x) / 2, f64(game.window_extent.y) / 2)
// 		}
//
// 		if camera.rotating_camera {
// 			glfw.SetInputMode(game.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
// 			glfw.SetInputMode(game.window, glfw.CURSOR, glfw.RAW_MOUSE_MOTION)
// 		} else {
// 			glfw.SetInputMode(game.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
// 		}
//
// 		if camera.rotating_camera && wants_rotate_camera {
// 			center := game.window_extent / 2.0
//
// 			mouse_x -= f64(center.x)
// 			mouse_y -= f64(center.y)
//
// 			yaw_delta = linalg.to_radians(f32(mouse_x)) * 0.1
// 			pitch_delta = linalg.to_radians(f32(mouse_y)) * -0.1
//
// 			camera.camera_rot += {f32(pitch_delta), f32(yaw_delta)}
// 		}
//
// 		camera.rotating_camera = wants_rotate_camera
// 	}
//
// 	if camera != nil {
// 		pitch := linalg.quaternion_angle_axis(camera.camera_rot.x, [3]f32{1, 0, 0})
// 		yaw := linalg.quaternion_angle_axis(camera.camera_rot.y, [3]f32{0, -1, 0})
// 		camera.rotation = yaw * pitch
//
// 		forward := linalg.quaternion_mul_vector3(camera.rotation, [3]f32{0, 0, -1})
// 		right := linalg.vector_cross3(forward, [3]f32{0, 1, 0})
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
// 			hit, ok := query_raycast_single(camera.translation, forward, 50, {.Dynamic, .Static}, true)
// 			if ok {
// 				if ball := get_entity(Ball, entity_id_from_rawptr(hit.actor.userData)); ball != nil {
// 					px.rigid_body_add_force_mut(ball.rigid, transmute(px.Vec3)(transmute([3]f32)hit.normal * -1 * 10), .Impulse, true)
// 				}
// 			}
// 		}
//
// 		accelleration: f32 = 120
//
// 		if key_w {
// 			camera.velocity += forward * accelleration * f32(delta_time)
// 		}
// 		if key_a {
// 			camera.velocity += right * -accelleration * f32(delta_time)
// 		}
// 		if key_s {
// 			camera.velocity += forward * -accelleration * f32(delta_time)
// 		}
// 		if key_d {
// 			camera.velocity += right * accelleration * f32(delta_time)
// 		}
// 		if key_space {
// 			camera.velocity += {0, 1, 0} * accelleration * f32(delta_time)
// 		}
// 		if key_shift {
// 			camera.velocity += {0, -1, 0} * accelleration * f32(delta_time)
// 		}
//
// 		camera.translation += camera.velocity * f32(delta_time)
// 		if linalg.length(camera.velocity) > 0.0 {
// 			friction: f32 = 0.0005
// 			camera.velocity = linalg.lerp(camera.velocity, 0.0, 1 - math.pow_f32(friction, f32(delta_time)))
// 		}
// 	}
// }

get_view_matrix :: proc(camera: ^Camera) -> matrix[4, 4]f32 {
	aspect_ratio := f32(game.window_extent.x) / f32(game.window_extent.y)

	translation := linalg.matrix4_translate(camera != nil ? camera.translation : {})
	rotation := linalg.matrix4_from_quaternion(camera != nil ? camera.rotation : {})

	return linalg.inverse(linalg.mul(translation, rotation))
}

get_projection_matrix :: proc(camera: ^Camera) -> matrix[4, 4]f32 {
	aspect_ratio := f32(game.window_extent.x) / f32(game.window_extent.y)

	projection_matrix := gfx.matrix4_infinite_perspective_z0_f32(
		linalg.to_radians(camera != nil ? camera.camera_fov_deg : 0),
		aspect_ratio,
		0.1,
	)
	projection_matrix[1][1] *= -1.0

	return projection_matrix
}

world_space_to_clip_space :: proc(view_projection: matrix[4, 4]f32, vec: [3]f32) -> ([2]f32, bool) {
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
