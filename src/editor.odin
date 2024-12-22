package game

import "base:runtime"
import "core:reflect"
import "core:fmt"

import im "deps:odin-imgui"

GAME_EDITOR :: true

Debug_Vis_Flag :: enum {
	ViewFrustum,
	ViewFromThirdPerson,
}

Debug_Vis_Flags :: bit_set[Debug_Vis_Flag;u32]

Editor_State :: struct {
	camera:          struct {
		pos:     Vec3,
		rot:     Vec3,
		fov_deg: f32,
	},
	debug_vis_flags: Debug_Vis_Flags,
}

debug_vis_flags :: proc() -> Debug_Vis_Flags {
	return game.editor.debug_vis_flags
}

editor_draw_imgui :: proc() {
	using runtime

	vis_flag_info := type_info_of(Debug_Vis_Flags).variant.(Type_Info_Bit_Set)
	elem := vis_flag_info.elem.variant.(Type_Info_Named).base.variant.(runtime.Type_Info_Enum)

	if im.Begin("Editor Flags") {
		for i in 0 ..< len(elem.values) {
			flag: u32 = 1 << u32(elem.values[i])
			im.CheckboxFlagsUintPtr(fmt.ctprint(elem.names[i]), transmute(^u32)&game.editor.debug_vis_flags, flag)
		}
	}
	im.End()
}
