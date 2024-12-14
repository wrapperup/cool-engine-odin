package game

import ma "vendor:miniaudio"

AudioManager :: struct {
	audio_engine: ma.engine,
}

audio_manager: ^AudioManager

init_audio_manager :: proc(mouse_locked := false) -> ^AudioManager {
	audio_manager = new(AudioManager)

	result := ma.engine_init(nil, &audio_manager.audio_engine)
	assert(result == .SUCCESS)

	return audio_manager
}

set_audio_manager :: proc(manager: ^AudioManager) {
	audio_manager = manager
}

play_sound :: proc(path: cstring) {
	ma.engine_play_sound(&audio_manager.audio_engine, path, nil)
}
