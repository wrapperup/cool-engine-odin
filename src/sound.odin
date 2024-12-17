package game

import ma "vendor:miniaudio"

SoundManager :: struct {
	sound_engine: ma.engine,
}

sound_manager: ^SoundManager

init_sound_manager :: proc(mouse_locked := false) -> ^SoundManager {
	sound_manager = new(SoundManager)

	config := ma.engine_config_init()
	result := ma.engine_init(&config, &sound_manager.sound_engine)
	assert(result == .SUCCESS)

	ma.engine_listener_set_cone(&sound_manager.sound_engine, 0, 40, 60, 10)

	return sound_manager
}

set_sound_manager :: proc(manager: ^SoundManager) {
	sound_manager = manager
}

play_sound :: proc(path: cstring) {
	ma.engine_play_sound(&sound_manager.sound_engine, path, nil)
}

play_sound_3d :: proc(path: cstring, position: Vec3) {
	sound := new(ma.sound)
	ma.sound_init_from_file(&sound_manager.sound_engine, path, {.DECODE}, nil, nil, sound);
	ma.sound_set_position(sound, position.x, position.y, position.z)
	ma.sound_set_looping(sound, true)
	ma.sound_start(sound)
}

set_listener_position :: proc(position: Vec3, forward: Vec3) {
	ma.engine_listener_set_position(&sound_manager.sound_engine, 0, position.x, position.y, position.z)
	ma.engine_listener_set_direction(&sound_manager.sound_engine, 0, forward.x, forward.y, forward.z)
}
