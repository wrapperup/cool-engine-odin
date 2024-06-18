package main

import "base:intrinsics"
import "base:runtime"
import "core:/math/linalg/hlsl"
import "core:fmt"
import "core:math/linalg"
import "core:testing"

// Entity Id is a packed u32 number that contains
// the liveness, generation and index in entity array.
// Live entities are always valid and updated.
EntityId :: bit_field u32 {
	live:       bool | 1,
	generation: u8   | 7,
	index:      u32  | 24,
}

TypedEntityId :: struct($T: typeid) {
	id: EntityId,
}

// The entity struct contains very common components
// that every entity needs. The core struct is designed
// to be reasonably cache-friendly, so keep it small when
// possible.
Entity :: struct {
	entity_id:   EntityId,
	type:        typeid,
	translation: [3]f32,
	velocity:    [3]f32,
	rotation:    linalg.Quaternionf32,
}

// Cache locality assurance
#assert (size_of(Entity) <= 64)

MAX_ENTITIES :: 16_777_216

entities: [dynamic]Entity

// Create typed entity
new_entity_subtype :: proc($T: typeid) -> ^T where intrinsics.type_is_subtype_of(T, ^Entity) {
	type_t := new(T)

	for &v, i in &entities {
		// Find empty hole in entity list
		if v.entity_id.live == false {
			// Update the entity gen pointer with the new entity
			type_t.entity_id = EntityId {
				live       = true,
				generation = v.generation,
				index      = cast(u32)i,
			}

			return type_t
		}
	}

	append(&entities, entity_gen_ptr)

	return type_t
}

// Returns a pointer to a new entity. If the entity array was 
new_entity_raw :: proc($T: typeid) -> (^Entity, bool) where intrinsics.type_is_subtype_of(T, ^Entity) {
	for &v, i in &entities {
		// Find empty hole in entity list
		if v.entity_id.live == false {
			// Update the entity gen pointer with the new entity
			type_t.entity_id = EntityId {
				live       = true,
				generation = v.generation,
				index      = cast(u32)i,
			}

			return type_t
		}
	}

	append(&entities, entity_gen_ptr)

	return type_t
}

// Create typed entity, returns a typed Id.
new_entity_with_typed_id :: proc(
	$T: typeid,
) -> (
	TypedEntityId(T),
	^T,
) where intrinsics.type_is_subtype_of(T, ^Entity) {
	entity := new_entity(T)
	return TypedEntityId(T){id = entity.entity_id}, entity
}

// Get entity safely. Generational index ensures that the entity
// you get is a valid entity, don't persist the pointer. Can return nil.
get_entity_untyped :: proc($T: typeid, id: EntityId) -> ^T where intrinsics.type_is_subtype_of(T, ^Entity) {
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
