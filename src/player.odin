package main

import "core:math"
import "core:math/linalg"

import "deps:jolt"

Player :: struct {
	using entity: ^Entity,
	character:    ^jolt.CharacterVirtual,
	coolness:     f32,
}

init_player :: proc(player: ^Player) {
	CHARACTER_HEIGHT_STANDING: f32 : 1.35
	CHARACTER_RADIUS_STANDING: f32 : 0.3
	CHARACTER_HEIGHT_CROUCHING: f32 : 0.8
	CHARACTER_RADIUS_CROUCHING: f32 : 0.3

	capsule := jolt.CapsuleShapeSettings_Create(CHARACTER_HEIGHT_STANDING / 2.0, CHARACTER_RADIUS_STANDING)

	translated_shape_settings := jolt.RotatedTranslatedShapeSettings_Create(
		(^jolt.ShapeSettings)(capsule),
		&{1, 0, 0, 0},
		&{0, 0.5 * CHARACTER_HEIGHT_STANDING + CHARACTER_RADIUS_STANDING, 0},
	)

	standing_shape := jolt.ShapeSettings_CreateShape((^jolt.ShapeSettings)(translated_shape_settings))

	settings := jolt.CharacterVirtualSettings_Create()
	settings.base.max_slope_angle = math.to_radians_f32(45.0)
	settings.max_strength = 100
	settings.base.shape = standing_shape
	settings.back_face_mode = .BACK_FACE_MODE_COLLIDE
	settings.character_padding = 0.02
	settings.penetration_recovery_speed = 1.0
	settings.predictive_contact_distance = 0.1
	settings.base.supporting_volume = {0, 1.0, 0, -CHARACTER_RADIUS_STANDING} // Accept contacts that touch the lower sphere of the capsule

	player.character = jolt.CharacterVirtual_Create(settings, &{0, 0, 0}, &{0, 0, 0, 0}, physics_system)
}

update_player :: proc(player: ^Player, delta_time: f64) {
	//jolt.CharacterPost

}
