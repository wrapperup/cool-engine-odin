package main

import "base:intrinsics"
import "base:runtime"
import "core:/math/linalg/hlsl"
import "core:fmt"
import "core:math/linalg"
import "core:slice"
import "core:testing"

RawSparseSet :: struct {
	sparse: runtime.Raw_Map,
	dense:  runtime.Raw_Dynamic_Array,
}

SparseSet :: struct($T: typeid) {
	sparse: map[EntityId]int, // id -> index in dense
	dense:  [dynamic]T,
}

assign_at_sparse_set :: proc(set: ^SparseSet($T), id: EntityId, data: T) -> ^T {
	index := len(set.dense)
	append(&set.dense, data)

	set.sparse[id] = index
	return &set.dense[index]
}

get_elem_sparse_set :: proc(set: ^SparseSet($T), id: EntityId) -> (data: ^T, ok: bool) {
	index := set.sparse[id] or_return
	return &set.dense[index], true
}

remove_elem_sparse_set :: proc(set: ^SparseSet($T), id: EntityId) -> (ok: bool) {
	assert(len(set.dense) > 0)

	deleted_index := set.sparse[id] or_return
	delete_key(&set.sparse, id)

	// Swaps last with index
	unordered_remove(&set.dense, deleted_index)
	old_index := len(set.dense)

	// Fix affected mapping that was moved
	for &k, &v in set.sparse {
		if old_index == v {
			set.sparse[k] = deleted_index	
		}
	}

	return true
}


// Entity System
// Works very similar to a ECS, except that "components" are just
// a subtype of an Entity. It's not as efficient as a normal ECS, but it's
// a lot faster than a classic OOP entity system.

// Querying subtypes is efficient, it works using an entity ID and a
// sparse set (like an ECS), and keeping subtype data dense for cache-locality.

// Entity Id is a packed u32 number that contains
// the liveness, generation and index in entity array.
EntityId :: distinct bit_field u32 {
	live:       bool | 1,
	generation: u8   | 7,
	index:      u32  | 24,
}

// Strongly typed ID, brings some checks back to compile-time to ensure
// the entity you queried is the correct type.
TypedEntityId :: struct($T: typeid) {
	using id: EntityId,
}

// The entity struct contains very common components
// that every entity needs. The core struct is designed
// to be reasonably cache-friendly, so keep it small when
// possible.
Entity :: struct {
	id:          EntityId,
	translation: [3]f32,
	velocity:    [3]f32,
	rotation:    linalg.Quaternionf32,
}

MAX_ENTITIES :: 16_777_216

NUM_ENTITIES: u32 = 0

// Holds cache-friendly, common data across entities
ENTITIES: [MAX_ENTITIES]Entity

// Maps typeid of T to SparseSet(T). 
//
// Safety: NEVER use this raw, use `new_or_get_entity_subtype_storage`
// or `get_entity_subtype_storage to get the correct typing.
SUBTYPE_STORAGE: map[typeid]rawptr

new_or_get_entity_subtype_storage :: proc($T: typeid) -> ^SparseSet(T) {
	if _, ok := SUBTYPE_STORAGE[T]; !ok {
		SUBTYPE_STORAGE[T] = new(SparseSet(T))
	}

	return get_entity_subtype_storage(T)
}

get_entity_subtype_storage :: proc "contextless" ($T: typeid) -> ^SparseSet(T) {
	return cast(^SparseSet(T))(SUBTYPE_STORAGE[T])
}

new_entity_subtype :: proc($T: typeid) -> ^T where intrinsics.type_is_subtype_of(T, ^Entity) {
	data := T{}
	data.entity = new_entity_raw()

	storage := new_or_get_entity_subtype_storage(T)

	return assign_at_sparse_set(storage, data.entity.id, data)
}

new_entity_subtype_id :: proc($T: typeid) -> (^T, TypedEntityId(T)) where intrinsics.type_is_subtype_of(T, ^Entity) {
	subtype := new_entity_subtype(T)

	return subtype, TypedEntityId(T){id = subtype.entity.id}
}

// Returns a pointer to a new entity. If the entity array was 
// extended, returns true, else if an entity was revived, false.
new_entity_raw :: proc() -> ^Entity {
	created_entity := Entity {
		id = {live = true, generation = 0, index = NUM_ENTITIES},
	}

	ENTITIES[NUM_ENTITIES] = created_entity
	NUM_ENTITIES += 1

	return &ENTITIES[NUM_ENTITIES - 1]
}

new_entity :: proc {
	new_entity_raw,
	new_entity_subtype,
}

// Get entity. Generational index ensures that the entity
// you get is a valid entity, don't persist the pointer. Can return nil.
get_entity_raw :: proc(id: EntityId) -> ^Entity {
	entity := ENTITIES[id.index]

	// Safety: Compare generation, this ensures that the entity we find isn't invalidated.
	if entity.id.generation != id.generation {
		return nil
	}

	return &ENTITIES[id.index]
}

get_entity_subtype :: proc($T: typeid, id: EntityId) -> ^T where intrinsics.type_is_subtype_of(T, ^Entity) {
	storage := get_entity_subtype_storage(T)
	type_t, ok := get_elem_sparse_set(storage, id)

	if !ok {
		return nil
	}

	// if type_t.id.generation != id.generation {
	// 	return nil
	// }

	return type_t
}

get_entity_subtype_typed :: proc(id: TypedEntityId($T)) -> ^T {
	return get_entity_subtype(T, id.id)
}

// Get entity. Generational index ensures that the entity
// you get is a valid entity, don't persist the pointer. Can return nil.
get_entity :: proc {
	get_entity_raw,
	get_entity_subtype,
	get_entity_subtype_typed,
}

// Removes entity from the entities list, and invalidates all existing handles.
remove_entity_raw :: proc(id: EntityId) -> bool {
	entity := &ENTITIES[id.index]

	// Compare generation 
	if entity.id.generation != id.generation {
		return false
	}

	// Invalidate all references to this entity.
	entity.id.live = false
	entity.id.generation += 1

	return true
}

remove_entity_subtype :: proc($T: typeid, id: EntityId) -> bool where intrinsics.type_is_subtype_of(T, ^Entity) {
	// Remove the raw entity data.
	if !remove_entity_raw(id) {
		return false
	}

	storage := get_entity_subtype_storage(T)

	return remove_elem_sparse_set(storage, id)
}

remove_entity_subtype_typed :: proc(id: TypedEntityId($T)) -> ^T {
	return remove_entity_subtype(T, id.id)
}

remove_entity :: proc {
	remove_entity_raw,
	remove_entity_subtype,
	remove_entity_subtype_typed,
}

entity_id_of :: proc(subtype_entity: ^$T) -> TypedEntityId(T) where intrinsics.type_is_subtype_of(T, ^Entity) {
	return TypedEntityId(T){id = subtype_entity.entity.id}
}

get_entities :: proc($T: typeid) -> []T {
	return get_entity_subtype_storage(T).dense[:]
}

len_entities :: proc($T: typeid) -> int {
	return len(get_entity_subtype_storage(T).dense)
}


parallel_for_entities_data :: proc(
	procedure: proc(entity: ^$T, index: int, data: rawptr = nil),
	data: rawptr = nil,
) where intrinsics.type_is_subtype_of(T, ^Entity) {
	storage := get_entity_subtype_storage(T)

	Parallel_For_Entity_Data :: struct {
		storage:   rawptr,
		data:      rawptr,
		procedure: proc(entity: ^T, index: int, data: rawptr),
	}

	parallel_for_entity_data := Parallel_For_Entity_Data {
		storage   = storage,
		data      = data,
		procedure = procedure,
	}

	parallel_for(len(storage.dense), proc(index: int, data: rawptr) {
			entity_data := cast(^Parallel_For_Entity_Data)data
			storage := cast(^SparseSet(T))entity_data.storage
			entity_data.procedure(&storage.dense[index], index, entity_data.data)
		}, &parallel_for_entity_data)
}

parallel_for_entities_no_data :: proc(
	procedure: proc(entity: ^$T, index: int),
) where intrinsics.type_is_subtype_of(T, ^Entity) {
	storage := get_entity_subtype_storage(T)

	Parallel_For_Entity_Data :: struct {
		storage:   rawptr,
		procedure: proc(entity: ^T, index: int),
	}

	parallel_for_entity_data := Parallel_For_Entity_Data {
		storage   = storage,
		procedure = procedure,
	}

	parallel_for(len(storage.dense), proc(index: int, data: rawptr) {
			entity_data := cast(^Parallel_For_Entity_Data)data
			storage := cast(^SparseSet(T))entity_data.storage
			entity_data.procedure(&storage.dense[index], index)
		}, &parallel_for_entity_data)
}

parallel_for_entities :: proc {
	parallel_for_entities_data,
	parallel_for_entities_no_data,
}
