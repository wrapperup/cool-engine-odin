package main

import "base:intrinsics"
import "core:/math/linalg/hlsl"
import "core:math/linalg"

GameState :: struct {
	environment: Environment,
	camera_id:   TypedEntityId(Camera),
	players:     [dynamic]^Player,
}

game_state: GameState

Camera :: struct {
	using entity:    Entity,
	//
	camera_rot:      [2]f32,
	camera_fov_deg:  f32,
	rotating_camera: bool,
	view_state:      enum i32 {
		SceneColor,
		SceneDepth,
		SunShadowDepth,
	},
}

Player :: struct {
	using entity: Entity,
}

Environment :: struct {
	sun_color:  hlsl.float3,
	sky_color:  hlsl.float3,
	bias:       f32,
	sun_pos:    [3]f32,
	sun_target: [3]f32,
}

PlayerController :: struct {
	input: struct {
		forward: bool,
		back: bool,
		left: bool,
		right: bool,
		jump: bool,
		crouch: bool,
	}
}
