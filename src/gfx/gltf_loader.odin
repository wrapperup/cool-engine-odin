package gfx

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:reflect"

import "vendor:cgltf"
import vk "vendor:vulkan"

Accessor_Buffer_Iterator :: struct($T: typeid) {
	accessor: ^cgltf.accessor,
	idx:      int,
	expr:     string,
	loc:      runtime.Source_Code_Location,
}

make_accessor_buf_iterator :: proc(
	accessor: ^cgltf.accessor,
	$T: typeid,
	expr := #caller_expression,
	loc := #caller_location,
) -> Accessor_Buffer_Iterator(T) {
	return Accessor_Buffer_Iterator(T){accessor, 0, expr, loc}
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

	assert(ok, iter.expr, iter.loc)

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
) where intrinsics.type_is_array(T) {
	// T = [N]U
	U :: intrinsics.type_elem_type(T)
	N :: len(T)

	ty_ok: bool = true

	// We don't support casting to different vec types.
	switch N {
	case 1:
		if type != .scalar do ty_ok = false
	case 2:
		if type != .vec2 do ty_ok = false
	case 3:
		if type != .vec3 do ty_ok = false
	case 4:
		if type != .vec4 do ty_ok = false
	case 16:
		if type != .mat4 do ty_ok = false
	}

	if !ty_ok {
		log_normal("Bad type:", typeid_of(T), type)
		ok = false
		return
	}

	switch component_type {
	case .r_8:
		reinterp_val := (cast(^[N]i8)value_ptr)^
		value = cast(T)linalg.array_cast(reinterp_val, U)
	case .r_16:
		reinterp_val := (cast(^[N]i16)value_ptr)^
		value = cast(T)linalg.array_cast(reinterp_val, U)
	case .r_8u:
		reinterp_val := (cast(^[N]u8)value_ptr)^
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
temp_parse_mesh_into_mesh_data :: proc(data: ^cgltf.data, mesh_idx: int) -> (indices: []u32, vertices: []Vertex, ok: bool) {
	mesh := &data.meshes[mesh_idx]
	primitive := &mesh.primitives[0]

	if (mesh_idx < len(data.skins)) {
		skin := &data.skins[mesh_idx]
		assert(skin != nil)
	}

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

load_mesh_from_file :: proc(path: cstring) -> (buffers: GPUMeshBuffers, ok: bool) {
	opts := cgltf.options{}
	data, result := cgltf.parse_file(opts, path)
	if result != .success do return

	result = cgltf.load_buffers(opts, data, path)
	if result != .success do return

	defer cgltf.free(data)

	indices, vertices := temp_parse_mesh_into_mesh_data(data, 0) or_return

	defer delete(indices)
	defer delete(vertices)

	buffers = create_mesh_buffers(indices, vertices)
	buffers.index_count = u32(len(indices))

	ok = true

	return
}

gltf_matrix_to_odin_matrix :: proc(in_m: [16]f32) -> hlsl.float4x4 {
	out_m: hlsl.float4x4

	out_m[0, 0] = in_m[0]
	out_m[1, 0] = in_m[1]
	out_m[2, 0] = in_m[2]
	out_m[3, 0] = in_m[3]

	out_m[0, 1] = in_m[4]
	out_m[1, 1] = in_m[5]
	out_m[2, 1] = in_m[6]
	out_m[3, 1] = in_m[7]

	out_m[0, 2] = in_m[8]
	out_m[1, 2] = in_m[9]
	out_m[2, 2] = in_m[10]
	out_m[3, 2] = in_m[11]

	out_m[0, 3] = in_m[12]
	out_m[1, 3] = in_m[13]
	out_m[2, 3] = in_m[14]
	out_m[3, 3] = in_m[15]

	return out_m
}

// Allocates two slices if successful. Make sure to free them when you're done.
temp_parse_mesh_into_skel_mesh_data :: proc(
	data: ^cgltf.data,
	mesh_idx: int,
) -> (
	indices: []u32,
	vertices: []Vertex,
	attrs: []SkeletonVertexAttribute,
	skeleton: Skeleton,
	skel_anim: SkeletalAnimation,
	ok: bool,
) {
	indices, vertices = temp_parse_mesh_into_mesh_data(data, mesh_idx) or_return

	mesh := &data.meshes[mesh_idx]
	primitive := &mesh.primitives[0]

	assert(mesh_idx < len(data.skins))

	skin := &data.skins[mesh_idx]
	assert(skin != nil)

	// Required for skeletal mesh.
	joints_idx := find_attribute(primitive, .joints) or_return
	weights_idx := find_attribute(primitive, .weights) or_return

	assert(primitive.attributes[joints_idx].data.count == primitive.attributes[weights_idx].data.count)
	attrs = make([]SkeletonVertexAttribute, primitive.attributes[joints_idx].data.count)

	{
		joints_it := make_accessor_buf_iterator(primitive.attributes[joints_idx].data, [4]u8)
		for val, i in accessor_buf_iterator(&joints_it) {
			attrs[i].joints = val
		}

		weights_it := make_accessor_buf_iterator(primitive.attributes[weights_idx].data, [4]f32)
		for val, i in accessor_buf_iterator(&weights_it) {
			attrs[i].weights = val
		}
	}

	{
		ptr_to_index: map[^cgltf.node]int

		reserve(&skeleton.inverse_bind_matrices, len(skin.joints))
		reserve(&skeleton.bind_matrices_ls, len(skin.joints))
		reserve(&skeleton.joint_tree, len(skin.joints))

		skeleton.joint_count = len(skin.joints)

		ibm_it := make_accessor_buf_iterator(skin.inverse_bind_matrices, [16]f32)
		for val, i in accessor_buf_iterator(&ibm_it) {
			append(&skeleton.inverse_bind_matrices, gltf_matrix_to_odin_matrix(val))
		}

		for &gltf_joint, i in skin.joints {
			// Calc the local-space transform of the joint.
			// TODO: We're just gonna assume that the skeleton is at the origin, so the world-space transform IS the local-space transform.
			gltf_local_matrix: [16]f32
			cgltf.node_transform_local(gltf_joint, &gltf_local_matrix[0])
			local_matrix := gltf_matrix_to_odin_matrix(gltf_local_matrix)

			ptr_to_index[gltf_joint] = len(skeleton.bind_matrices_ls)
			append(&skeleton.bind_matrices_ls, local_matrix)
		}

		// Create hierarchical tree structure for joints (used later for calcing joint matrices)
		for &gltf_joint, i in skin.joints {
			children: [dynamic]u32
			reserve(&children, len(gltf_joint.children))

			for &node_child in gltf_joint.children {
				index, ok := ptr_to_index[node_child]
				assert(ok, "Child node is not a joint.")

				append(&children, u32(index))
			}

			append(&skeleton.joint_tree, children)
		}

		// TODO: TESTING: Grab first animation TESTING
		animation := data.animations[0]

		joint_anims: map[int]JointTrack

		for &channel, i in animation.channels {
			joint_index, ok := ptr_to_index[channel.target_node]
			if ok {
				joint_anim, ok_j := &joint_anims[joint_index]
				if !ok_j {
					// TODO: this is kinda ass ngl
					joint_anims[joint_index] = JointTrack {}
					joint_anim = &joint_anims[joint_index]
				}

				#partial switch channel.target_path {
				case .translation:
					input_it := make_accessor_buf_iterator(channel.sampler.output, [3]f32)
					for val, i in accessor_buf_iterator(&input_it) {
						append(&joint_anim.keyframes_translation, val)
					}
				case .rotation:
					input_it := make_accessor_buf_iterator(channel.sampler.output, [4]f32)
					for val, i in accessor_buf_iterator(&input_it) {
						q := quaternion(w = val.w, x = val.x, y = val.y, z = val.z)
						append(&joint_anim.keyframes_rotation, q)
					}
				case .scale:
					input_it := make_accessor_buf_iterator(channel.sampler.output, [3]f32)
					for val, i in accessor_buf_iterator(&input_it) {
						append(&joint_anim.keyframes_scale, val)
					}
				case:
					panic("Unsupported animation channel type.")
				}
			}
		}

		reserve(&skel_anim.joint_animations, len(joint_anims))
		for k in 0 ..< len(joint_anims) {
			append(&skel_anim.joint_animations, joint_anims[k])
		}

		skel_anim.keyframe_count = u32(len(skel_anim.joint_animations[0].keyframes_translation))
		skel_anim.fps = 30.0
	}

	ok = true

	return
}

load_skel_mesh_from_file :: proc(path: cstring) -> (buffers: GPUSkelMeshBuffers, skeleton: Skeleton, anim: SkeletalAnimation, ok: bool) {
	opts := cgltf.options{}
	data, result := cgltf.parse_file(opts, path)
	if result != .success do return

	result = cgltf.load_buffers(opts, data, path)
	if result != .success do return

	defer cgltf.free(data)

	indices, vertices, attrs, skel, an := temp_parse_mesh_into_skel_mesh_data(data, 0) or_return
	skeleton = skel
	anim = an

	defer delete(indices)
	defer delete(vertices)
	defer delete(attrs)

	buffers = create_skel_mesh_buffers(indices, vertices, attrs)

	ok = true

	return
}

create_skel_mesh_buffers :: proc(indices: []u32, vertices: []Vertex, attrs: []SkeletonVertexAttribute) -> GPUSkelMeshBuffers {
	assert(len(attrs) > 0)
	assert(len(vertices) == len(attrs))

	new_surface: GPUSkelMeshBuffers

	new_surface.mesh_buffers = create_mesh_buffers(indices, vertices)

	attrs_buffer_size := vk.DeviceSize(size_of(SkeletonVertexAttribute) * len(attrs))

	new_surface.skel_vert_attrs_buffer = create_buffer(
		attrs_buffer_size,
		{.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
		.GPU_ONLY,
	)
	new_surface.skel_vert_attrs_address = get_buffer_device_address(new_surface.skel_vert_attrs_buffer)

	// Copy data into buffer via staging buffer
	{
		staging := create_buffer(attrs_buffer_size, {.TRANSFER_SRC}, .CPU_ONLY)

		data := staging.info.pMappedData

		// TODO: Make these slices somehow? maybe make a helper method for staging buffers?
		mem.copy(data, raw_data(attrs), int(attrs_buffer_size))

		if cmd, ok := immediate_submit(); ok {
			attrs_copy := vk.BufferCopy {
				dstOffset = 0,
				srcOffset = 0,
				size      = attrs_buffer_size,
			}

			vk.CmdCopyBuffer(cmd, staging.buffer, new_surface.skel_vert_attrs_buffer.buffer, 1, &attrs_copy)
		}

		destroy_buffer(&staging)
	}

	return new_surface
}
