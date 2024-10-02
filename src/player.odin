package main

import "core:math"

import "deps:jolt"

Player :: struct {
	using entity: ^Entity,
	character:    ^jolt.CharacterVirtual,
	coolness:     f32,
}

// init_player :: proc() {
// 	player := get_entity(game.state.player_id)
//
// 	settings := jolt.CharacterVirtualSettings_Create()
// 	settings.base.max_slope_angle = math.to_radians(45.0)
// 	settings.mMaxStrength = 100
// 	settings.mShape = mStandingShape
// 	settings.mBackFaceMode = .BACK_FACE_;
// 	settings.mCharacterPadding = 0.02;
// 	settings.mPenetrationRecoverySpeed = 1.0;
// 	settings.mPredictiveContactDistance = 0.1;
// 	settings.mSupportingVolume = Plane(Vec3::sAxisY(), -cCharacterRadiusStanding); // Accept contacts that touch the lower sphere of the capsule
// 	settings.mEnhancedInternalEdgeRemoval = sEnhancedInternalEdgeRemoval;
// 	settings.mInnerBodyShape = sCreateInnerBody? mInnerStandingShape : nullptr;
// 	settings.mInnerBodyLayer = Layers::MOVING;
// 	player.character = jolt.CharacterVirtual_Create
// }
//
// update_player :: proc() {
// 	player := get_entity(game.state.player_id)
//
// }
