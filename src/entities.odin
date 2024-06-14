package main

import "base:intrinsics"
import "base:runtime"
import "core:/math/linalg/hlsl"
import "core:fmt"
import "core:math/linalg"
import "core:testing"

// Entity Id is a packed u32 number that contains
// the generation and index in entity array.
// First byte: u8 generation
// Remaining bytes: u24 index
EntityId :: bit_field u32 {
	generation: u8  | 8,
	index:      u32 | 24,
}

TypedEntityId :: struct($T: typeid) {
	id: EntityId,
}

Entity :: struct {
	entity_id:   EntityId,
	translation: [3]f32,
	velocity:    [3]f32,
	rotation:    linalg.Quaternionf32,
}

EntityGenerationalPointer :: struct {
	entity_ptr: ^Entity,
	type:       typeid,
	generation: u8,
}

entities: [dynamic]EntityGenerationalPointer

// Create typed entity
new_entity :: proc($T: typeid) -> ^T where intrinsics.type_is_subtype_of(T, Entity) {
	type_t := new(T)

	for &v, i in &entities {
		// Find empty hole in entity list
		if v.entity_ptr == nil {
			// Update the entity gen pointer with the new entity
			type_t.entity_id = EntityId {
				generation = v.generation,
				index      = cast(u32)i,
			}
			v.entity_ptr = type_t
			v.type = T

			return type_t
		}
	}

	entity_gen_ptr := EntityGenerationalPointer {
		entity_ptr = type_t,
		generation = 0,
		type = T
	}

	type_t.entity_id = EntityId {
		generation = 0,
		index      = cast(u32)len(entities),
	}

	append(&entities, entity_gen_ptr)

	return type_t
}

// Create typed entity, returns a typed Id.
new_entity_with_typed_id :: proc($T: typeid) -> (TypedEntityId(T), ^T) where intrinsics.type_is_subtype_of(T, Entity) {
	entity := new_entity(T)
	return TypedEntityId(T){id = entity.entity_id}, entity
}

// Get entity safely. Generational index ensures that the entity
// you get is a valid entity, don't persist the pointer. Can return nil.
get_entity_untyped :: proc($T: typeid, id: EntityId) -> ^T where intrinsics.type_is_subtype_of(T, Entity) {
	entity_gen_ptr := entities[id.index]

	// Safety: Check type
	if T != entity_gen_ptr.type {
		return nil
	}

	// Safety: Compare generation, this ensures that the entity we find isn't invalidated.
	if entity_gen_ptr.generation != id.generation {
		return nil
	}

	return cast(^T)entity_gen_ptr.entity_ptr
}

// Removes entity from the entities list, and invalidates all existing handles.
remove_entity_untyped :: proc(id: EntityId) -> bool {
	entity_gen_ptr := &entities[id.index]

	// Compare generation 
	if entity_gen_ptr.generation != id.generation {
		return false
	}

	// TODO: Make this safe. Don't require user to provide the entity type.
	free(cast(rawptr)entity_gen_ptr.entity_ptr)

	// Increase generation and nullify the pointer, this 
	// will invalidate all existing handles to this entity.
	entity_gen_ptr.entity_ptr = nil
	entity_gen_ptr.generation += 1

	return true
}

// Get entity safely. Generational index ensures that the entity
// you get is a valid entity, don't persist the pointer. Can return nil.
// Includes additional built-in typesafety.
get_entity_typed :: proc(id: TypedEntityId($T)) -> ^T {
	return get_entity_untyped(T, id.id)
}

// Removes entity from the entities list, and invalidates all existing handles.
remove_entity_typed :: proc(id: TypedEntityId($T)) -> bool {
	return remove_entity_untyped(id.id)
}

get_entity :: proc {
	get_entity_untyped,
	get_entity_typed,
}

remove_entity :: proc {
	remove_entity_untyped,
	remove_entity_typed,
}
