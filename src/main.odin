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

import "deps:jolt"
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

	physics_init()

	init_game()

	game_loop()
}

init_window :: proc(width, height: c.int) -> glfw.WindowHandle {
	glfw.Init()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	return glfw.CreateWindow(i32(width), i32(height), "Vulkan", nil, nil)
}

init_game :: proc() {
	game.window = init_window(1700, 900)

	if !gfx.init(&game.renderer, game.window) {
		fmt.println("Graphics could not be initialized.")
	}

	init_game_draw()

	camera := new_entity(Camera)
	player := new_entity(Player)
	player.translation = {0.0, 100.0, 100.0}
	for i in 0 ..< 1024 {
		ball := new_entity(Ball)
		ball.translation = {
			(rand.float32() - 0.5) * 0.01 * f32(i),
			5.0 * f32(i),
			(rand.float32() - 0.5) * 0.01 * f32(i),
		}

		ball.body = jolt.GetBodyInterface(physics_system)

		sphere_shape_settings := jolt.SphereShapeSettings_Create(1.0)
		sss: jolt.BodyCreationSettings
		in_p := hlsl.float3{0, 2, 0}
		in_r := hlsl.float4{0, 0, 0, 1}
		jolt.BodyCreationSettings_Set(
			&sss,
			jolt.ShapeSettings_CreateShape((^jolt.ShapeSettings)(sphere_shape_settings)),
			&in_p,
			&in_r,
			.MOTION_TYPE_DYNAMIC,
			BroadPhaseLayers_Moving,
		)
		ball.body_id = jolt.BodyInterface_CreateAndAddBody(ball.body, &sss, .ACTIVATION_ACTIVATE)
		jolt.BodyInterface_SetPosition(
			ball.body,
			ball.body_id,
			cast(^hlsl.float3)(&ball.translation),
			.ACTIVATION_ACTIVATE,
		)
	}

	jolt.PhysicsSystem_SetGravity(physics_system, &{0, -0.98 * 4, 0})

	camera.translation = {-9, 9.5, 14}
	camera.camera_rot = {-0.442, 0.448}
	camera.camera_fov_deg = 45
	camera.view_state = .SceneColor

	game.state = GameState {
		camera_id = entity_id_of(camera),
		player_id = entity_id_of(player),
		environment = Environment {
			sun_pos = {12, 15, 10},
			sun_target = 0.0,
			sun_color = 1.0,
			sky_color = {.4, .35, .55},
			bias = 0.001,
		},
	}

	jolt.PhysicsSystem_OptimizeBroadPhase(physics_system)
}

game_loop :: proc() {
	for !glfw.WindowShouldClose(game.window) {
		start := time.now()

		update()

		start_render := time.now()

		update_buffers()

		cmd := gfx.begin_draw(&game.renderer)
		draw(cmd)
		gfx.end_draw(&game.renderer, cmd)

		game.frame_time_render = f32(time.since(start_render)) / f32(time.Millisecond)

		game.frame_time_total = f32(time.since(start)) / f32(time.Millisecond)
		game.delta_time = f64(time.since(start)) / f64(time.Second)

		// Free temp allocations
		free_all(context.temp_allocator)
	}
}

update :: proc() {
	update_game_state(game.delta_time)
	// physics_update()
	update_imgui()
}

update_game_state :: proc(delta_time: f64) {
	start_game_state := time.now()
	camera := get_entity(game.state.camera_id)

	{
		yaw_delta_a, pitch_delta_a := glfw.GetCursorPos(game.window)

		yaw_delta := linalg.to_radians((f32(yaw_delta_a) / f32(game.renderer.window_extent.width)) - 0.5) * 100
		pitch_delta := linalg.to_radians((f32(pitch_delta_a) / f32(game.renderer.window_extent.height)) - 0.5) * -50

		wants_rotate_camera := glfw.GetMouseButton(game.window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS
		if wants_rotate_camera {
			glfw.SetCursorPos(game.window, f64(game.renderer.window_extent.width) / 2, f64(game.renderer.window_extent.height) / 2)
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
		camera.rotation = linalg.mul(yaw, pitch)

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

	parallel_for_entities(proc(entity: ^Player, index: int) {
		entity.translation.y += f32(entity.coolness) * 0.001
	})

	// parallel_for_entities(proc(entity: ^Ball, index: int) {
	// 	pos: hlsl.float3
	// 	rot: hlsl.float4
	// 	jolt.BodyInterface_GetPosition(entity.body, entity.body_id, &pos)
	// 	jolt.BodyInterface_GetRotation(entity.body, entity.body_id, &rot)
	//
	// 	entity.translation = cast([3]f32)pos
	// 	entity.rotation = transmute(linalg.Quaternionf32)rot
	// })

	ball_iter := make_entity_iter(Ball)
	for ball in iter_entities(&ball_iter) {
		pos: hlsl.float3
		rot: hlsl.float4
		jolt.BodyInterface_GetPosition(ball.body, ball.body_id, &pos)
		jolt.BodyInterface_GetRotation(ball.body, ball.body_id, &rot)

		ball.translation = cast([3]f32)pos
		ball.rotation = transmute(linalg.Quaternionf32)rot
	}

	game.frame_time_game_state = f32(time.since(start_game_state)) / f32(time.Millisecond)

	collision_steps := 1

	start_physics := time.now()
	jolt.PhysicsSystem_Update(physics_system, 1.0 / 60.0, collision_steps, 0, jta, js)
	game.frame_time_physics = f32(time.since(start_physics)) / f32(time.Millisecond)
}

update_players :: proc() {

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
				fmt.ctprintf(
					"%s Entities (num: %d)",
					type_info_of(key).variant.(runtime.Type_Info_Named).name,
					storage_raw.dense.len,
				),
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
		im.InputFloat3("sun_color", cast(^[3]f32)(&game.state.environment.sun_color))
		im.InputFloat3("sky_color", cast(^[3]f32)(&game.state.environment.sky_color))
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
}


@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1


//Just some code you can copy paste and try to run to check if things are running properly this is not the full hello
physics_init :: proc() {
	in_broad_phase_layer_interface.GetNumBroadPhaseLayers = get_num_broad_pl
	in_broad_phase_layer_interface.GetBroadPhaseLayer = get_broad_phase_layer

	in_object_vs_broad_phase_layer_filter.ShouldCollide = should_collide
	in_object_layer_pair_filter.ShouldCollide = should_collide_object_layer

	jolt.RegisterDefaultAllocator()
	jolt.RegisterTypes()
	jta = jolt.TempAllocator_Create(1024 * 1024 * 10)
	js = jolt.JobSystem_Create(jolt.cMaxPhysicsJobs, jolt.cMaxPhysicsBarriers, 4)

	in_max_bodies: u32 = 1024
	in_num_body_mutexes: u32 = 0
	in_max_body_pairs: u32 = 4096 * 1
	in_max_constraints: u32 = 4096 * 1

	physics_system = jolt.PhysicsSystem_Create(
		in_max_bodies,
		in_num_body_mutexes,
		in_max_body_pairs,
		in_max_constraints,
		in_broad_phase_layer_interface,
		in_object_vs_broad_phase_layer_filter,
		in_object_layer_pair_filter,
	)

	contact_listener: jolt.ContactListenerVTable
	contact_listener.OnContactAdded = contact_added_test
	jolt.SetContactListener(physics_system, &contact_listener)

	{
		body_interface = jolt.GetBodyInterface(physics_system)

		a := hlsl.float3{100, 1, 100}
		floor_shape_settings := jolt.BoxShapeSettings_Create(&a)
		fmt.println("box shape settings create")
		floor_shape := jolt.ShapeSettings_CreateShape((^jolt.ShapeSettings)(floor_shape_settings))
		fmt.println("floor shape create")

		bcs: jolt.BodyCreationSettings
		in_p := hlsl.float3{0, -1, 0}
		in_r := hlsl.float4{0, 0, 0, 1}
		jolt.BodyCreationSettings_Set(&bcs, floor_shape, &in_p, &in_r, .MOTION_TYPE_STATIC, BroadPhaseLayers_Moving)
		floor := jolt.BodyInterface_CreateBody(body_interface, &bcs)

		jolt.BodyInterface_AddBody(body_interface, jolt.Body_GetID(floor), .ACTIVATION_DONT_ACTIVATE)
	}

	{
		body_interface = jolt.GetBodyInterface(physics_system)
		a := hlsl.float3{20, 10, 1}
		floor_shape_settings := jolt.BoxShapeSettings_Create(&a)
		fmt.println("box shape settings create")
		floor_shape := jolt.ShapeSettings_CreateShape((^jolt.ShapeSettings)(floor_shape_settings))
		fmt.println("floor shape create")

		bcs: jolt.BodyCreationSettings
		in_p := hlsl.float3{0, 0, 20}
		in_r := hlsl.float4{0, 0, 0, 1}
		jolt.BodyCreationSettings_Set(&bcs, floor_shape, &in_p, &in_r, .MOTION_TYPE_STATIC, BroadPhaseLayers_Moving)
		floor := jolt.BodyInterface_CreateBody(body_interface, &bcs)

		jolt.BodyInterface_AddBody(body_interface, jolt.Body_GetID(floor), .ACTIVATION_DONT_ACTIVATE)
	}
	{
		body_interface = jolt.GetBodyInterface(physics_system)
		a := hlsl.float3{20, 10, 1}
		floor_shape_settings := jolt.BoxShapeSettings_Create(&a)
		fmt.println("box shape settings create")
		floor_shape := jolt.ShapeSettings_CreateShape((^jolt.ShapeSettings)(floor_shape_settings))
		fmt.println("floor shape create")

		bcs: jolt.BodyCreationSettings
		in_p := hlsl.float3{0, 0, -20}
		in_r := hlsl.float4{0, 0, 0, 1}
		jolt.BodyCreationSettings_Set(&bcs, floor_shape, &in_p, &in_r, .MOTION_TYPE_STATIC, BroadPhaseLayers_Moving)
		floor := jolt.BodyInterface_CreateBody(body_interface, &bcs)

		jolt.BodyInterface_AddBody(body_interface, jolt.Body_GetID(floor), .ACTIVATION_DONT_ACTIVATE)
	}
	{
		body_interface = jolt.GetBodyInterface(physics_system)
		a := hlsl.float3{1, 10, 20}
		floor_shape_settings := jolt.BoxShapeSettings_Create(&a)
		fmt.println("box shape settings create")
		floor_shape := jolt.ShapeSettings_CreateShape((^jolt.ShapeSettings)(floor_shape_settings))
		fmt.println("floor shape create")

		bcs: jolt.BodyCreationSettings
		in_p := hlsl.float3{20, 0, 0}
		in_r := hlsl.float4{0, 0, 0, 1}
		jolt.BodyCreationSettings_Set(&bcs, floor_shape, &in_p, &in_r, .MOTION_TYPE_STATIC, BroadPhaseLayers_Moving)
		floor := jolt.BodyInterface_CreateBody(body_interface, &bcs)

		jolt.BodyInterface_AddBody(body_interface, jolt.Body_GetID(floor), .ACTIVATION_DONT_ACTIVATE)
	}
	{
		body_interface = jolt.GetBodyInterface(physics_system)
		a := hlsl.float3{1, 10, 20}
		floor_shape_settings := jolt.BoxShapeSettings_Create(&a)
		fmt.println("box shape settings create")
		floor_shape := jolt.ShapeSettings_CreateShape((^jolt.ShapeSettings)(floor_shape_settings))
		fmt.println("floor shape create")

		bcs: jolt.BodyCreationSettings
		in_p := hlsl.float3{-20, 0, 0}
		in_r := hlsl.float4{0, 0, 0, 1}
		jolt.BodyCreationSettings_Set(&bcs, floor_shape, &in_p, &in_r, .MOTION_TYPE_STATIC, BroadPhaseLayers_Moving)
		floor := jolt.BodyInterface_CreateBody(body_interface, &bcs)

		jolt.BodyInterface_AddBody(body_interface, jolt.Body_GetID(floor), .ACTIVATION_DONT_ACTIVATE)
	}

	// sphere_shape_settings := jolt.SphereShapeSettings_Create(0.5)
	// sss: jolt.BodyCreationSettings
	// in_p = hlsl.float3{0, 2, 0}
	// in_r = hlsl.float4{0, 0, 0, 1}
	// jolt.BodyCreationSettings_Set(
	// 	&sss,
	// 	jolt.ShapeSettings_CreateShape((^jolt.ShapeSettings)(sphere_shape_settings)),
	// 	&in_p,
	// 	&in_r,
	// 	.MOTION_TYPE_DYNAMIC,
	// 	BroadPhaseLayers_Moving,
	// )
	// sphere_id = jolt.BodyInterface_CreateAndAddBody(body_interface, &sss, .ACTIVATION_ACTIVATE)
	// fmt.println(sss)
}

physics_update :: proc() {
	step := 0
	for jolt.BodyInterface_IsActive(body_interface, sphere_id) {

		pos: hlsl.float3
		jolt.BodyInterface_GetCenterOfMassPosition(body_interface, sphere_id, &pos)
		linvel: hlsl.float3
		jolt.BodyInterface_GetLinearVelocity(body_interface, sphere_id, &linvel)

		collision_steps := 1
		fixed_delta_time: f32 = 1.0 / 60.0
		jolt.PhysicsSystem_Update(physics_system, fixed_delta_time, collision_steps, 0, jta, js)
	}
}

//interface and callback stuff
get_num_broad_pl :: proc "c" () -> c.uint32_t {
	context = runtime.default_context()
	return (c.uint32_t)(BroadPhaseLayers.NumLayers)
}

get_broad_phase_layer :: proc "c" (in_layer: jolt.ObjectLayer) -> jolt.BroadPhaseLayer {
	return (jolt.BroadPhaseLayer)(broad_phase_layer_map[in_layer])
}

contact_added_test :: proc "c" (
	b: ^jolt.Body,
	b2: ^jolt.Body,
	in_manifold: ^jolt.ContactManifold,
	io_settings: ^jolt.ContactSettings,
) {
	context = runtime.default_context()
}

should_collide :: proc "c" (in_layer: jolt.ObjectLayer, in_layer2: jolt.BroadPhaseLayer) -> bool {
	context = runtime.default_context()
	switch int(in_layer) {
	case (int)(BroadPhaseLayers_NonMoving):
		return int(in_layer2) == int(BroadPhaseLayers_Moving)
	case int(BroadPhaseLayers_Moving):
		return true
	case:
		//JPH_ASSERT(false);
		return false
	}
	return false
}

should_collide_object_layer :: proc "c" (in_layer: jolt.ObjectLayer, in_layer2: jolt.ObjectLayer) -> bool {
	context = runtime.default_context()

	switch int(in_layer) {
	case int(BroadPhaseLayers_NonMoving):
		return int(in_layer2) == int(BroadPhaseLayers_Moving) // Non moving only collides with moving
	case int(BroadPhaseLayers_Moving):
		return true // Moving collides with everything
	case:
		//JPH_ASSERT(false);
		return false
	}
	return false
}

physics_system: ^jolt.PhysicsSystem
jta: ^jolt.TempAllocator
js: ^jolt.JobSystem
body_interface: ^jolt.BodyInterface

sphere_id: jolt.BodyID

BroadPhaseLayers :: enum c.uint8_t {
	NonMoving = 0,
	Moving    = 1,
	NumLayers = 2,
}

BroadPhaseLayers_NonMoving: jolt.ObjectLayer : 0
BroadPhaseLayers_Moving: jolt.ObjectLayer : 1
BroadPhaseLayers_NumLayers: jolt.ObjectLayer : 2

broad_phase_layer_map: map[jolt.ObjectLayer]BroadPhaseLayers

in_broad_phase_layer_interface: jolt.BroadPhaseLayerInterfaceVTable
in_object_vs_broad_phase_layer_filter: jolt.ObjectVsBroadPhaseLayerFilterVTable
in_object_layer_pair_filter: jolt.ObjectLayerPairFilterVTable
