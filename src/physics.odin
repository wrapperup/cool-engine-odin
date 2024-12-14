package game

import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import px "deps:physx-odin"

GamePhysicsFilter :: enum u32 {
	NonWalkable,
}

GamePhysicsFilterSet :: bit_set[GamePhysicsFilter;u32]

get_words_from_filter :: proc(filter_set: GamePhysicsFilterSet) -> (word0, word1, word2, word3: u32) {
	bits: u32 = transmute(u32)filter_set

	return bits, 0, 0, 0
}

// oh my fucking god why does this leak... fucking dumb
RAYCAST_BUFFER_BASE_STRUCT := px.create_raycast_buffer()

matrix_from_transform :: proc(transform: px.Transform) -> matrix[4, 4]f32 {
	translation := linalg.matrix4_translate_f32(transmute(Vec3)transform.p)
	rotation := linalg.matrix4_from_quaternion(transmute(quaternion128)transform.q)

	return translation * rotation
}

init_raycast_buffer :: proc() -> px.RaycastCallback {
	buffer := RAYCAST_BUFFER_BASE_STRUCT^
	return buffer
}

query_raycast_single :: proc(
	origin: Vec3,
	unit_dir: Vec3,
	distance: f32,
	filter: GamePhysicsFilterSet = {},
	query_flags: px.QueryFlags_Set = {.Static},
	debug: bool = false,
) -> (
	px.RaycastHit,
	bool,
) {
	hit := init_raycast_buffer()
	filter_data := px.filter_data_new_2(get_words_from_filter(filter))
	query_filter := px.query_filter_data_new_1(filter_data, query_flags)

	ok := px.scene_query_system_base_raycast(
		game.phys.scene,
		transmute(px.Vec3)origin,
		transmute(px.Vec3)unit_dir,
		distance,
		&hit,
		{.FaceIndex, .Normal, .Position},
		query_filter,
		nil,
		nil,
		{.SimdGuard},
	)

	if debug {
		pos := transmute(Vec3)hit.block.position
		normal := transmute(Vec3)hit.block.normal

		debug_draw_line(origin, pos, dots = true)
		debug_draw_line(pos, pos + normal, dots = false)
	}

	return hit.block, ok
}

collision_filter_shader :: proc "c" (info: ^px.FilterShaderCallbackInfo) -> px.FilterFlags_Set {
	context = runtime.default_context()

	info.pair_flags^ = {.SolveContact, .DetectDiscreteContact, .NotifyTouchFound}

	return {}
}

collision_callback :: proc "c" (user_data: rawptr, pair_header: ^px.ContactPairHeader, pairs: ^px.ContactPair, nb_pairs: u32) {
	context = runtime.default_context()

	for actor in pair_header.actors {
		if actor.userData != nil {
			// entity_id := entity_id_from_rawptr(actor.userData)

			// if player := get_entity_subtype(Player, entity_id); player != nil {
			// 	on_player_collide(player)
			// }
		}
	}
}

trigger_callback :: proc "c" (user_data: rawptr, pairs: ^px.TriggerPair, nb_pairs: u32) {
	context = runtime.default_context()
	fmt.println("trigger")
}

constraint_break_callback :: proc "c" (user_data: rawptr, constraints: ^px.ConstraintInfo, nb_pairs: u32) {
	context = runtime.default_context()
	fmt.println("constraint break")
}

wake_sleep_callback :: proc "c" (user_data: rawptr, actors: [^]^px.Actor, count: u32, is_wake: bool) {
	context = runtime.default_context()
	fmt.println("wake_sleep", is_wake)
}

advance_callback :: proc "c" (user_data: rawptr, body_buffer: [^]^px.RigidBody, pose_buffer: [^]px.Transform, count: u32) {
	context = runtime.default_context()
	fmt.println("advance")
}

user_error_callback :: proc "c" (code: px.ErrorCode, message: cstring, file: cstring, line: i32, user_data: rawptr) {
	context = runtime.default_context()
	fmt.println("Physx Error:", code, message, file, line)
}
