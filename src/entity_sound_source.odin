package game

import ma "vendor:miniaudio"

SoundSource :: struct {
	using entity: ^Entity,
	sound:        ma.sound,
}

init_sound_source :: proc(source: ^SoundSource, file_path: cstring, loop: b32 = false, rolloff: f32 = 1) {
	ma.sound_init_from_file(&sound_manager.sound_engine, file_path, {.DECODE}, nil, nil, &source.sound)
	ma.sound_set_looping(&source.sound, loop)
	ma.sound_set_rolloff(&source.sound, rolloff)
	ma.sound_start(&source.sound)
}

destroy_sound_source :: proc(source: ^SoundSource) {
    ma.sound_uninit(&source.sound)
}
