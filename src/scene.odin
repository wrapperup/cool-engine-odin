package game

import "core:mem/virtual"

import gfx "gfx"

Scene :: struct {
    arena: virtual.Arena,
    gpu_arena: gfx.ResourceArena,
}
