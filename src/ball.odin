package game

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"

import im "deps:odin-imgui"
import px "deps:physx-odin"

import "gfx"

Ball :: struct {
	using entity:       ^Entity,
	material:           MaterialId,
	num:                int,
	rigid:              ^px.RigidDynamic,

	// Skeleton stuff
	skel_mesh_instance: SkeletalMeshInstance,
	skel_anim:          ^SkeletalAnimation,
	skel_animator:      SkeletonAnimator,
	use_game_time:      bool,
	sample_time:        f32,
}

init_ball :: proc(ball: ^Ball, pos: [3]f32, vel: [3]f32 = 0, skeleton: ^Skeleton, anim: ^SkeletalAnimation) {
	ball.skel_mesh_instance = init_skeletal_mesh_instance(skeleton, anim)
	ball.material = 0

	init_skeleton_animator(&ball.skel_animator, skeleton, anim)

	using px

	ball.num = len_entities(Ball) - 1

	sphere_material := physics_create_material_mut(game.phys.physics, 0.9, 0.5, 0.1)
	// geo := capsule_geometry_new(1, 1.0)
	geo := sphere_geometry_new(1.3)
	// shape := px.physics_create_shape_mut(
	// 	game.phys.physics,
	// 	&geo,
	// 	sphere_material^,
	// 	false,
	// 	{.SimulationShape, .Visualization},
	// )
	// px.shape_set_local_pose_mut(shape, transform_new_1({0, 1.5, 0}))
	// filter_data := px.filter_data_new_2(get_words_from_filter({.NonWalkable}))
	// px.shape_set_query_filter_data_mut(shape, filter_data)

	// ball.rigid = create_dynamic_1(
	// 	game.phys.physics,
	// 	transform_new_1(transmute(Vec3)pos),
	// 	shape,
	// 	10.0,
	// )

	ball.rigid = create_dynamic(
		game.phys.physics,
		transform_new_1(transmute(Vec3)pos),
		&geo,
		sphere_material,
		10.0,
		transform_new_1({0, 0, 0}),
	)

	rigid_body_set_angular_damping_mut(ball.rigid, 0.1)
	rigid_body_set_linear_damping_mut(ball.rigid, 0.1)
	// rigid_body_set_rigid_body_flags_mut(ball.rigid, {.Kinematic})
	// rigid_dynamic_set_rigid_dynamic_lock_flags_mut(
	// 	ball.rigid,
	// 	{.LockAngularX, .LockAngularY, .LockAngularZ},
	// )
	scene_add_actor_mut(game.phys.scene, ball.rigid, nil)
	px.rigid_dynamic_set_sleep_threshold_mut(ball.rigid, 0.1)

	base := cast(^Actor)ball.rigid
	base.userData = entity_id_to_rawptr(ball.id)

	px.rigid_dynamic_set_linear_velocity_mut(ball.rigid, transmute(px.Vec3)vel, true)
}

update_ball_fixed :: proc(ball: ^Ball) {
	sample_animation(&ball.skel_animator, ball.sample_time)

	using px

	pose := rigid_actor_get_global_pose(ball.rigid)
	ball.translation = transmute([3]f32)pose.p
	ball.rotation = transmute(quaternion128)pose.q
	rigid_body_add_force_mut(ball.rigid, {0, 0, 0}, .Force, true)
}

on_ball_collide :: proc(ball: ^Ball) {
	fmt.println("hi", ball)
}
