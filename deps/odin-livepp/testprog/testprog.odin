package main

import "core:fmt"
import "base:runtime"
import SDL "vendor:sdl2"
import lpp "../"

Thing :: struct {
    cool: proc() -> (),
}

GLOBAL_THING := Thing {
}

main :: proc () {
    // create a default agent, loading the Live++ agent from the given path, e.g. "ThirdParty/LivePP"
    local_preferences := lpp.CreateDefaultLocalPreferences()
    lpp_agent := lpp.CreateDefaultAgentANSI(&local_preferences, "./LivePP");

    // bail out in case the agent is not valid
    if !lpp.IsValidDefaultAgent(&lpp_agent) {
        fmt.println("Oh noes!");
        return;
    }

    // enable Live++ for all loaded modules
    lpp_agent.EnableModule(lpp.GetCurrentModulePath(), .ALL_IMPORT_MODULES, nil, nil);

	WINDOW_WIDTH  :: 854
	WINDOW_HEIGHT :: 480
	
	window := SDL.CreateWindow("Odin SDL2 Demo", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, {.OPENGL})
	if window == nil {
		return
	}
	defer SDL.DestroyWindow(window)

    GLOBAL_THING.cool = thing_from_stuff;
	
	loop: for {
        //thing_from_stuff()

		// event polling
		event: SDL.Event
		for SDL.PollEvent(&event) {
			// #partial switch tells the compiler not to error if every case is not present
			#partial switch event.type {
			case .KEYDOWN:
				#partial switch event.key.keysym.sym {
				case .ESCAPE:
                    break loop
					// labelled control flow
				}
			case .QUIT:
				// labelled control flow
				break loop
			}
		}
	}

    GLOBAL_THING.cool()
    thing_from_stuff()
    thing_from_stuff()
    thing_from_stuff()
    thing_from_stuff()

    // destroy the Live++ agent
    lpp.DestroyDefaultAgent(&lpp_agent);
}
