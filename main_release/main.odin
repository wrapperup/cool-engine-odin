package main

import "core:sys/windows"

import game "../src"

main :: proc() {
	when ODIN_OS == .Windows {
		// Use UTF-8 for console output (fixes emojis/unicode/utf-8 shenanigans)
		windows.SetConsoleOutputCP(.UTF8)
	}

	window := game.game_init_window()
	game.game_init(window)

	window_open := true
	for window_open {
		window_open = game.game_update()
		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	game.game_shutdown()
}

// Make game use good GPU on laptops.

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
