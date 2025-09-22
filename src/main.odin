package game

import "core:log"
import "core:sys/windows"

GENERATING_META :: #config(GENERATING_META, false)

main :: proc() {
	when ODIN_OS == .Windows {
		// Use UTF-8 for console output (fixes emojis/unicode/utf-8 shenanigans)
		windows.SetConsoleOutputCP(.UTF8)
	}

    LOG_OPTIONS :: log.Options {
        .Level,
    }

    context.logger = log.create_console_logger(opt = LOG_OPTIONS)

    when GENERATING_META {
        main_meta()
    } else {
        main_game()
    }
}
