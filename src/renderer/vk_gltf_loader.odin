package renderer

import "base:intrinsics"
import "core:fmt"
import "core:math/linalg"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:reflect"
import "vendor:cgltf"

Accessor_Buffer_Iterator :: struct($T: typeid) {
	accessor: ^cgltf.accessor,
	idx:      int,
}

make_accessor_buf_iterator :: proc(accessor: ^cgltf.accessor, $T: typeid) -> Accessor_Buffer_Iterator(T) {
	return Accessor_Buffer_Iterator(T){accessor, 0}
}

accessor_buf_iterator :: proc(iter: ^Accessor_Buffer_Iterator($T)) -> (T, int, bool) {
	idx := iter.idx

	if uint(idx) >= iter.accessor.count {
		return 0, idx, false
	}

	value_ptr := mem.ptr_offset(
		cast(^u8)iter.accessor.buffer_view.buffer.data,
		int(iter.accessor.offset) + int(iter.accessor.buffer_view.offset) + (idx * int(iter.accessor.stride)),
	)

	iter.idx += 1

	cast_value, ok := try_cast_accessor_type(T, value_ptr, iter.accessor.component_type, iter.accessor.type)

	return cast_value, idx, ok
}

try_cast_accessor_type :: proc(
	$T: typeid,
	value_ptr: rawptr,
	component_type: cgltf.component_type,
	type: cgltf.type,
) -> (
	value: T,
	ok: bool,
) {
	when intrinsics.type_is_array(T) {
		value, ok = try_cast_vec_type(T, value_ptr, component_type, type)
	} else when intrinsics.type_is_integer(T) || intrinsics.type_is_unsigned(T) || intrinsics.type_is_float(T) {
		value, ok = try_cast_numeric_type(T, value_ptr, component_type)
	}

	return
}

try_cast_numeric_type :: proc(
	$T: typeid,
	value_ptr: rawptr,
	component_type: cgltf.component_type,
) -> (
	T,
	bool,
) where intrinsics.type_is_integer(T) ||
	intrinsics.type_is_float(T) ||
	intrinsics.type_is_unsigned(T) {
	when intrinsics.type_is_unsigned(T) {
		return try_cast_uint_type(T, value_ptr, component_type)
	} else when intrinsics.type_is_float(T) {
		return try_cast_float_type(T, value_ptr, component_type)
	} else when intrinsics.type_is_integer(T) {
		return try_cast_int_type(T, value_ptr, component_type)
	}
}

try_cast_int_type :: proc(
	$T: typeid,
	value_ptr: rawptr,
	component_type: cgltf.component_type,
) -> (
	value: T,
	ok: bool,
) where intrinsics.type_is_integer(T) {
	#partial switch component_type {
	case .r_8:
		value = cast(T)((cast(^i8)value_ptr)^)
	case .r_16:
		value = cast(T)((cast(^i16)value_ptr)^)
	case:
		return
	}

	ok = true

	return
}

try_cast_uint_type :: proc(
	$T: typeid,
	value_ptr: rawptr,
	component_type: cgltf.component_type,
) -> (
	value: T,
	ok: bool,
) where intrinsics.type_is_unsigned(T) {

	#partial switch component_type {
	case .r_8u:
		value = cast(T)((cast(^u8)value_ptr)^)
	case .r_16u:
		value = cast(T)((cast(^u16)value_ptr)^)
	case .r_32u:
		value = cast(T)((cast(^u32)value_ptr)^)
	case:
		return
	}

	ok = true

	return
}

try_cast_float_type :: proc(
	$T: typeid,
	value_ptr: rawptr,
	component_type: cgltf.component_type,
) -> (
	value: T,
	ok: bool,
) where intrinsics.type_is_float(T) {
	switch component_type {
	case .r_32f:
		value = cast(T)((cast(^f32)value_ptr)^)
	case default:
		return
	}

	ok = true

	return
}

try_cast_vec_type :: proc(
	$T: typeid,
	value_ptr: rawptr,
	component_type: cgltf.component_type,
	type: cgltf.type,
) -> (
	value: T,
	ok: bool,
) where len(T) >=
	1,
	len(T) <=
	4,
	intrinsics.type_is_array(T) {
	// T = [N]U
	U :: intrinsics.type_elem_type(T)
	N :: len(T)

	// We don't support casting to different vec types.
	switch N {
	case 1:
		if type != .scalar do return
	case 2:
		if type != .vec2 do return
	case 3:
		if type != .vec3 do return
	case 4:
		if type != .vec4 do return
	}

	switch component_type {
	case .r_8:
		reinterp_val := (cast(^[N]i8)value_ptr)^
		value = cast(T)linalg.array_cast(reinterp_val, U)
	case .r_8u:
		reinterp_val := (cast(^[N]u8)value_ptr)^
		value = cast(T)linalg.array_cast(reinterp_val, U)
	case .r_16:
		reinterp_val := (cast(^[N]i16)value_ptr)^
		value = cast(T)linalg.array_cast(reinterp_val, U)
	case .r_16u:
		reinterp_val := (cast(^[N]u16)value_ptr)^
		value = cast(T)linalg.array_cast(reinterp_val, U)
	case .r_32u:
		reinterp_val := (cast(^[N]u32)value_ptr)^
		value = cast(T)linalg.array_cast(reinterp_val, U)
	case .r_32f:
		reinterp_val := (cast(^[N]f32)value_ptr)^
		value = cast(T)linalg.array_cast(reinterp_val, U)
	case .invalid:
		return
	}

	ok = true

	return
}

find_attribute :: proc(prim: ^cgltf.primitive, type: cgltf.attribute_type) -> (int, bool) {
	for attribute, i in &prim.attributes {
		if attribute.type == type {
			return i, true
		}
	}

	return 0, false
}

// Allocates two slices if successful. Make sure to free them when you're done.
temp_parse_mesh_into_mesh_data :: proc(
	data: ^cgltf.data,
	mesh_idx: int,
) -> (
	indices: []u32,
	vertices: []Vertex,
	ok: bool,
) {
	primitive := &data.meshes[mesh_idx].primitives[0]

	pos_idx := find_attribute(primitive, .position) or_return
	norm_idx, norm_ok := find_attribute(primitive, .normal)
	color_idx, color_ok := find_attribute(primitive, .color)
	uv_idx, uv_ok := find_attribute(primitive, .texcoord)

	index_buffer_data := cast([^]u16)primitive.indices.buffer_view.data
	indices = make([]u32, primitive.indices.count)

	vertex_buffer_data := cast([^]u16)primitive.attributes[pos_idx].data.buffer_view.data
	vertices = make([]Vertex, primitive.attributes[pos_idx].data.count)

	i_it := make_accessor_buf_iterator(primitive.indices, u32)
	for val, i in accessor_buf_iterator(&i_it) {
		indices[i] = val
	}

	v_it := make_accessor_buf_iterator(primitive.attributes[pos_idx].data, hlsl.float3)
	data := primitive.attributes[pos_idx].data
	for val, i in accessor_buf_iterator(&v_it) {
		vertices[i].position = val
	}

	if norm_ok {
		data := primitive.attributes[norm_idx].data
		n_it := make_accessor_buf_iterator(data, hlsl.float3)
		for val, i in accessor_buf_iterator(&n_it) {
			vertices[i].normal = val
		}
	}

	if color_ok {
		c_it := make_accessor_buf_iterator(primitive.attributes[color_idx].data, hlsl.float4)
		for val, i in accessor_buf_iterator(&c_it) {
			vertices[i].color = val
		}
	}
	if uv_ok {
		uv_it := make_accessor_buf_iterator(primitive.attributes[uv_idx].data, hlsl.float2)
		for val, i in accessor_buf_iterator(&uv_it) {
			vertices[i].uv_x = val.x
			vertices[i].uv_y = val.y
		}
	}

	ok = true

	return indices, vertices, ok
}
