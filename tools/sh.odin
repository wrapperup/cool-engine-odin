package tools

import "core:flags"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:sys/windows"
import "core:time"

import vk "vendor:vulkan"

import "../src/gfx"
import ktx "deps:odin-libktx"
import vma "deps:odin-vma"

import impl "../src"

ShCommand :: struct {
	input: cstring `args:"pos=0,required" usage:"Input file."`,
}

main :: proc() {
	when ODIN_OS == .Windows {
		// use utf-8 for console output (fixes emojis/unicode/utf-8 shenanigans)
		windows.SetConsoleOutputCP(.UTF8)
	}
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	command: ShCommand
	error := flags.parse(&command, os.args[1:])
	switch v in error {
	case flags.Help_Request:
		fmt.println("Usage:")
		fmt.println("  sh <input>")
	case flags.Parse_Error:
		fmt.println(v.message)
	case flags.Open_File_Error:
		fmt.println("could not open", v.filename)
	case flags.Validation_Error:
		fmt.println(v.message)
	}

	start_time := time.now()

	coeffs := impl.process_sh_coefficients_from_file(fmt.ctprint(command.input))

	fmt.println(coeffs)

	fmt.println("Done in", time.since(start_time))

	free_all()
}
