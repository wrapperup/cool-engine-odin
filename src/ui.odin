package game

import "gfx"

UIShape :: enum {
    Circle,
}

UICommand :: struct {
    index: u64,
    shape: UIShape,
}

UICircle :: struct {
    center: Vec2,
    radius: f32,
}

UIState :: struct {
    commands: [dynamic]UICommand,
    circles: [dynamic]UICircle
}

GPUUIState :: struct {
    commands: gfx.GPUPtr(UICommand),
    circles: gfx.GPUPtr(UICircle),
}

ui_end :: proc() {
    ui_state := &game.render_state.ui_state

    _ui_reset(ui_state)
}

_ui_reset :: proc(ui_state: ^UIState) {
    clear(&ui_state.commands)
    clear(&ui_state.circles)
}

ui_draw_circle :: proc(center: Vec2, radius: f32) {
    // ui_state := &game.render_state.ui_state
    //
    // command := UICommand {
    //     index = u64(len(ui_state.circles)),
    //     shape = .Circle,
    // }
    //
    // circle := UICircle {
    //     center = center,
    //     radius = radius,
    // }
}
