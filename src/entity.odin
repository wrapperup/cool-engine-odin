package main

import "core:math/linalg"

Entity :: struct {
	translation: [3]f32,
	velocity:    [3]f32,
	rotation:    linalg.Quaternionf32,
}

entities: [dynamic]Entity

// Packed data
EntityId :: distinct u32

new_entity :: proc($T: typeid) -> T {
	type_t := T{}
	append(&entities, Entity{})
	type_t.entity = &entities[len(entities) - 1]

	return type_t
}
