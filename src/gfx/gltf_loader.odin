package gfx

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:reflect"
import "core:slice"

import "vendor:cgltf"
import vk "vendor:vulkan"

import mikk "deps:odin-mikktspace"

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

find_custom_attribute :: proc(prim: ^cgltf.primitive, name: cstring) -> (int, bool) {
	for attribute, i in &prim.attributes {
		if attribute.type == .custom && attribute.name == name {
			return i, true
		}
	}

	return 0, false
}

create_mesh_buffers :: proc(mesh: Mesh, loc := #caller_location) -> GPUMeshBuffers {
	index_count := u32(len(mesh.indices))
	vertex_count := u32(len(mesh.vertices))

	assert(index_count > 0)
	assert(vertex_count > 0)

	vertex_buffer_size := vk.DeviceSize(size_of(Vertex) * vertex_count)
	index_buffer_size := vk.DeviceSize(size_of(u32) * index_count)

	new_surface: GPUMeshBuffers
	new_surface.index_count = index_count
	new_surface.vertex_count = vertex_count

	new_surface.vertex_buffer = create_buffer(
		vertex_buffer_size,
		{.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
		.GPU_ONLY,
		loc = loc,
	)
	new_surface.index_buffer = create_buffer(index_buffer_size, {.INDEX_BUFFER, .TRANSFER_DST}, .GPU_ONLY, loc = loc)

	return new_surface
}

staging_write_mesh_buffers :: proc(buffers: ^GPUMeshBuffers, mesh: Mesh, loc := #caller_location) {
	vertex_buffer_size := vk.DeviceSize(size_of(Vertex) * len(mesh.vertices))
	index_buffer_size := vk.DeviceSize(size_of(u32) * len(mesh.indices))

	assert(buffers.index_count == u32(len(mesh.indices)))
	assert(buffers.vertex_count == u32(len(mesh.vertices)))

	staging := create_buffer(vertex_buffer_size + index_buffer_size, {.TRANSFER_SRC}, .CPU_ONLY, loc = loc)

	write_buffer_slice(&staging, mesh.vertices)
	write_buffer_slice(&staging, mesh.indices, vertex_buffer_size)

	if cmd, ok := immediate_submit(); ok {
		vertex_copy := vk.BufferCopy {
			dstOffset = 0,
			srcOffset = 0,
			size      = vertex_buffer_size,
		}

		index_copy := vk.BufferCopy {
			dstOffset = 0,
			srcOffset = vertex_buffer_size,
			size      = index_buffer_size,
		}

		vk.CmdCopyBuffer(cmd, staging.buffer, buffers.vertex_buffer.buffer, 1, &vertex_copy)
		vk.CmdCopyBuffer(cmd, staging.buffer, buffers.index_buffer.buffer, 1, &index_copy)
	}

	destroy_buffer(&staging)
}


// Allocates two slices if successful. Make sure to free them when you're done.
parse_gltf_mesh_into_mesh :: proc(data: ^cgltf.data, mesh_idx: int) -> (mesh: Mesh, ok: bool) {
	gltf_mesh := &data.meshes[mesh_idx]
	primitive := &gltf_mesh.primitives[0]

	if (mesh_idx < len(data.skins)) {
		skin := &data.skins[mesh_idx]
		assert(skin != nil)
	}

	pos_idx := find_attribute(primitive, .position) or_return
	norm_idx, norm_ok := find_attribute(primitive, .normal)
	color_idx, color_ok := find_attribute(primitive, .color)
	uv_idx, uv_ok := find_attribute(primitive, .texcoord)
	//lightmap_uv_idx, lightmap_uv_ok := find_attribute(primitive, .texcoord)
	tangent_idx, tangent_ok := find_attribute(primitive, .tangent)

	mesh.indices = make([]u32, primitive.indices.count)

	{
		it := make_accessor_buf_iterator(primitive.indices, u32)
		for val, i in accessor_buf_iterator(&it) {
			mesh.indices[i] = val
		}
	}

	{
		data := primitive.attributes[pos_idx].data
		mesh.vertices = make([]Vertex, data.count)

		it := make_accessor_buf_iterator(data, hlsl.float3)
		for val, i in accessor_buf_iterator(&it) {
			mesh.vertices[i].position = val
		}
	}

	if norm_ok {
		data := primitive.attributes[norm_idx].data
		it := make_accessor_buf_iterator(data, hlsl.float3)
		for val, i in accessor_buf_iterator(&it) {
			mesh.vertices[i].normal = val
		}
	}

	if color_ok {
		data := primitive.attributes[color_idx].data
		it := make_accessor_buf_iterator(data, hlsl.float4)
		for val, i in accessor_buf_iterator(&it) {
			mesh.vertices[i].color = val
		}
	}

	if uv_ok {
		data := primitive.attributes[uv_idx].data
		it := make_accessor_buf_iterator(data, hlsl.float2)
		for val, i in accessor_buf_iterator(&it) {
			mesh.vertices[i].uv_x = val.x
			mesh.vertices[i].uv_y = val.y
		}
	}

	if tangent_ok {
		data := primitive.attributes[tangent_idx].data
		it := make_accessor_buf_iterator(data, hlsl.float4)
		for val, i in accessor_buf_iterator(&it) {
			mesh.vertices[i].tangent = val
		}
	} else if uv_ok && norm_ok {
		// Generate tangents if we have normals + uv and no tangents are included.
		get_vertex_index :: proc(pContext: ^mikk.Context, iFace: int, iVert: int) -> int {
			gltf_mesh := cast(^Mesh)pContext.user_data

			indices_index := iVert + (iFace * get_num_vertices_of_face(pContext, iFace))
			index := gltf_mesh.indices[indices_index]

			return int(index)
		}

		get_num_faces :: proc(pContext: ^mikk.Context) -> int {
			gltf_mesh := cast(^Mesh)pContext.user_data
			return len(gltf_mesh.indices) / 3
		}

		get_num_vertices_of_face :: proc(pContext: ^mikk.Context, iFace: int) -> int {
			return 3
		}

		get_position :: proc(pContext: ^mikk.Context, iFace: int, iVert: int) -> [3]f32 {
			gltf_mesh := cast(^Mesh)pContext.user_data
			return gltf_mesh.vertices[get_vertex_index(pContext, iFace, iVert)].position
		}

		get_normal :: proc(pContext: ^mikk.Context, iFace: int, iVert: int) -> [3]f32 {
			gltf_mesh := cast(^Mesh)pContext.user_data
			return gltf_mesh.vertices[get_vertex_index(pContext, iFace, iVert)].normal
		}

		get_tex_coord :: proc(pContext: ^mikk.Context, iFace: int, iVert: int) -> [2]f32 {
			gltf_mesh := cast(^Mesh)pContext.user_data
			vertex := &gltf_mesh.vertices[get_vertex_index(pContext, iFace, iVert)]
			return {vertex.uv_x, vertex.uv_y}
		}

		set_t_space_basic :: proc(pContext: ^mikk.Context, fvTangent: [3]f32, fSign: f32, iFace: int, iVert: int) {
			gltf_mesh := cast(^Mesh)pContext.user_data
			tangent := &gltf_mesh.vertices[get_vertex_index(pContext, iFace, iVert)].tangent

			// Not sure why I need to flip these? Seems to be fine though.
			tangent.xyz = -fvTangent
			tangent.w = -fSign
		}

		interface := mikk.Interface {
			get_num_faces            = get_num_faces,
			get_num_vertices_of_face = get_num_vertices_of_face,
			get_position             = get_position,
			get_normal               = get_normal,
			get_tex_coord            = get_tex_coord,
			set_t_space_basic        = set_t_space_basic,
		}

		ctx := mikk.Context {
			interface = &interface,
			user_data = &mesh,
		}

		tangent_ok = mikk.generate_tangents(&ctx)
	}

	assert(tangent_ok)

	ok = true

	return mesh, ok
}

Mesh :: struct {
	indices:  []u32,
	// TODO: Maybe store this as AOS instead
	vertices: []Vertex,
}

SkeletalMesh :: struct {
	using mesh: Mesh,
	attrs:      []SkeletonVertexAttribute,
}


load_mesh_from_file :: proc(path: cstring, loc := #caller_location) -> (mesh: Mesh, ok: bool) {
	opts := cgltf.options{}
	data, result := cgltf.parse_file(opts, path)
	if result != .success do return

	result = cgltf.load_buffers(opts, data, path)
	if result != .success do return

	defer cgltf.free(data)

	return parse_gltf_mesh_into_mesh(data, 0)
}

load_gpu_mesh_from_file :: proc(path: cstring, loc := #caller_location) -> (gpu_mesh: GPUMeshBuffers, ok: bool) {
	opts := cgltf.options{}
	data, result := cgltf.parse_file(opts, path)
	if result != .success do return

	result = cgltf.load_buffers(opts, data, path)
	if result != .success do return

	defer cgltf.free(data)

	mesh := parse_gltf_mesh_into_mesh(data, 0) or_return
	return upload_mesh_to_gpu(mesh, loc = loc), true
}

defer_destroy_gpu_mesh :: proc(arena: ^VulkanArena, gpu_mesh: GPUMeshBuffers) {
	defer_destroy_buffer(arena, gpu_mesh.vertex_buffer)
	defer_destroy_buffer(arena, gpu_mesh.index_buffer)
}

upload_mesh_to_gpu :: proc(mesh: Mesh, loc := #caller_location) -> GPUMeshBuffers {
	buffers := create_mesh_buffers(mesh, loc = loc)
	staging_write_mesh_buffers(&buffers, mesh)
	buffers.index_count = u32(len(mesh.indices))

	return buffers
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
parse_gltf_mesh_into_skel_mesh :: proc(
	data: ^cgltf.data,
	mesh_idx: int,
) -> (
	skel_mesh: SkeletalMesh,
	skeleton: Skeleton,
	skel_anim: SkeletalAnimation,
	ok: bool,
) {
	skel_mesh.mesh = parse_gltf_mesh_into_mesh(data, mesh_idx) or_return

	gltf_mesh := &data.meshes[mesh_idx]
	primitive := &gltf_mesh.primitives[0]

	assert(mesh_idx < len(data.skins))

	skin := &data.skins[mesh_idx]
	assert(skin != nil)

	// Required for skeletal mesh.
	joints_idx := find_attribute(primitive, .joints) or_return
	weights_idx := find_attribute(primitive, .weights) or_return

	assert(primitive.attributes[joints_idx].data.count == primitive.attributes[weights_idx].data.count)
	skel_mesh.attrs = make([]SkeletonVertexAttribute, primitive.attributes[joints_idx].data.count)

	{
		it := make_accessor_buf_iterator(primitive.attributes[joints_idx].data, [4]u8)
		for val, i in accessor_buf_iterator(&it) {
			skel_mesh.attrs[i].joints = val
		}
	}
	{
		it := make_accessor_buf_iterator(primitive.attributes[weights_idx].data, [4]f32)
		for val, i in accessor_buf_iterator(&it) {
			skel_mesh.attrs[i].weights = val
		}
	}

	{
		ptr_to_index: map[^cgltf.node]int

		reserve(&skeleton.inverse_bind_matrices, len(skin.joints))
		reserve(&skeleton.bind_matrices_ls, len(skin.joints))
		reserve(&skeleton.joint_tree, len(skin.joints))

		skeleton.joint_count = len(skin.joints)

		it := make_accessor_buf_iterator(skin.inverse_bind_matrices, [16]f32)
		for val, i in accessor_buf_iterator(&it) {
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
					joint_anims[joint_index] = JointTrack{}
					joint_anim = &joint_anims[joint_index]
				}

				#partial switch channel.target_path {
				case .translation:
					it := make_accessor_buf_iterator(channel.sampler.output, [3]f32)
					for val, i in accessor_buf_iterator(&it) {
						append(&joint_anim.keyframes_translation, val)
					}
				case .rotation:
					it := make_accessor_buf_iterator(channel.sampler.output, [4]f32)
					for val, i in accessor_buf_iterator(&it) {
						q := quaternion(w = val.w, x = val.x, y = val.y, z = val.z)
						append(&joint_anim.keyframes_rotation, q)
					}
				case .scale:
					it := make_accessor_buf_iterator(channel.sampler.output, [3]f32)
					for val, i in accessor_buf_iterator(&it) {
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

load_skel_mesh_from_file :: proc(path: cstring, loc := #caller_location) -> (skeleton: Skeleton, anim: SkeletalAnimation, ok: bool) {
	opts := cgltf.options{}
	data, result := cgltf.parse_file(opts, path)
	assert(result == .success)

	result = cgltf.load_buffers(opts, data, path)
	if result != .success do return

	defer cgltf.free(data)

	skel_mesh, skel, an := parse_gltf_mesh_into_skel_mesh(data, 0) or_return
	skeleton = skel
	anim = an

	skeleton.buffers = create_skel_mesh_buffers(skel_mesh, loc = loc)
	staging_write_skel_mesh_buffers(&skeleton.buffers, skel_mesh, loc = loc)

	ok = true

	return
}

defer_destroy_gpu_skel_mesh :: proc(arena: ^VulkanArena, gpu_mesh: GPUSkelMeshBuffers) {
	defer_destroy_gpu_mesh(arena, gpu_mesh)
	defer_destroy_buffer(arena, gpu_mesh.skel_vert_attrs_buffer)
}

// Creates the buffers, but doesn't fill them.
create_skel_mesh_buffers :: proc(skel_mesh: SkeletalMesh, loc := #caller_location) -> GPUSkelMeshBuffers {
	assert(len(skel_mesh.attrs) > 0)
	assert(len(skel_mesh.vertices) == len(skel_mesh.attrs))

	new_surface: GPUSkelMeshBuffers
	new_surface.mesh_buffers = create_mesh_buffers(skel_mesh, loc = loc)
	new_surface.attrs_count = u32(len(skel_mesh.attrs))

	new_surface.skel_vert_attrs_buffer = create_buffer(
		vk.DeviceSize(size_of(SkeletonVertexAttribute) * len(skel_mesh.attrs)),
		{.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
		.GPU_ONLY,
		loc = loc,
	)

	return new_surface
}

staging_write_skel_mesh_buffers :: proc(buffers: ^GPUSkelMeshBuffers, skel_mesh: SkeletalMesh, loc := #caller_location) {
	assert(len(skel_mesh.attrs) > 0)
	assert(len(skel_mesh.vertices) == len(skel_mesh.attrs))

	staging_write_mesh_buffers(buffers, skel_mesh)

	attrs_buffer_size := vk.DeviceSize(size_of(SkeletonVertexAttribute) * len(skel_mesh.attrs))

	staging_write_buffer_slice(&buffers.skel_vert_attrs_buffer, skel_mesh.attrs)
}
