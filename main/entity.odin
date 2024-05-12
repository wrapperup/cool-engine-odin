package main

import "core:math/linalg"

Entity :: struct {
	translation: [3]f32,
	rotation:    linalg.Quaternionf32,
}

EntityManager :: struct {
	entities: [dynamic]^Entity,
}

EntityId :: distinct u16

Bob :: struct {
	entity_id:   u16,
	coolness:    i32,
	awesomeness: f32,
}

@(private)
_manager := EntityManager{}
