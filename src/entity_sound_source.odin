package game

import ma "vendor:miniaudio"

SoundSource :: struct {
	using entity: ^Entity,
	sound:        ma.sound,
}

init_sound_source :: proc(
	source: ^SoundSource,
	file_path: cstring,
	loop: b32 = false,
	rolloff: f32 = 1,
	spatialization := true,
	volume: f32 = 1.0,
) {
	extra_flags: ma.sound_flags = spatialization ? {} : {.NO_SPATIALIZATION}
	ma.sound_init_from_file(&sound_manager.sound_engine, file_path, {.DECODE} + extra_flags, nil, nil, &source.sound)
	ma.sound_set_looping(&source.sound, loop)
	ma.sound_set_rolloff(&source.sound, rolloff)
	ma.sound_set_volume(&source.sound, volume)
	ma.sound_start(&source.sound)
}

destroy_sound_source :: proc(source: ^SoundSource) {
	ma.sound_uninit(&source.sound)
}
