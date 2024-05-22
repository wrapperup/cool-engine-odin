package main

import "core:/math/linalg/hlsl"

GameState :: struct {
	environment: Environment,
	camera:      Camera,
	players:     [dynamic]^Player,
}

game_state: GameState

Camera :: struct {
	using entity:    ^Entity,
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
	using entity: ^Entity,
}

Environment :: struct {
	sun_color:  hlsl.float3,
	sky_color:  hlsl.float3,
	bias:       f32,
	sun_pos:    [3]f32,
	sun_target: [3]f32,
}

init_game_state :: proc() {
	camera := new_entity(Camera)
	camera.translation = {-9, 9.5, 14}
	camera.camera_rot = {-0.442, 0.448}
	camera.camera_fov_deg = 45
	camera.view_state = .SceneColor

	game_state = GameState {
		camera = camera,
		environment = Environment {
			sun_pos = {12, 15, 10},
			sun_target = 0.0,
			sun_color = 1.0,
			sky_color = {.4, .35, .55},
			bias = 0.001,
		},
	}
}
