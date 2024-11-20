package game

import "core:fmt"
import "core:math/linalg/hlsl"

import px "deps:physx-odin"

import "gfx"

StaticMesh :: struct {
	using entity: ^Entity,
	mesh:         gfx.GPUMeshBuffers,
	material:     MaterialId,
	body:         ^px.RigidStatic,
}

init_static_mesh :: proc(static_mesh: ^StaticMesh, mesh_file_name: cstring, material: MaterialId) {
	mesh, ok := gfx.load_mesh_from_file(mesh_file_name)
	assert(ok)

	gpu_mesh := gfx.upload_mesh_to_gpu(mesh)
	gfx.defer_destroy_gpu_mesh(&gfx.renderer().global_arena, gpu_mesh)

	tolerances_scale := px.tolerances_scale_new(1, 10)
	params := px.cooking_params_new(tolerances_scale)

	fmt.println(params)

	points_data := make([]hlsl.float3, len(mesh.vertices))
	defer delete(points_data)

	for vertex, i in mesh.vertices {
		points_data[i] = vertex.position
	}

	mesh_desc := px.triangle_mesh_desc_new()

	mesh_desc.points.count = u32(len(mesh.vertices))
	mesh_desc.points.stride = size_of(hlsl.float3)
	mesh_desc.points.data = raw_data(points_data)

	mesh_desc.triangles.count = u32(len(mesh.indices)) / 3
	mesh_desc.triangles.stride = 3 * size_of(u32)
	mesh_desc.triangles.data = raw_data(mesh.indices)

	// valid := px.validate_triangle_mesh(params, mesh_desc)
	// assert(valid)

	result: px.TriangleMeshCookingResult
	tri_mesh := px.create_triangle_mesh(params, mesh_desc, px.physics_get_physics_insertion_callback_mut(game.phys.physics), &result)
	assert(result == .Success)

	geometry := px.triangle_mesh_geometry_new(tri_mesh, px.mesh_scale_new_1(1), {})

	phys_material := px.physics_create_material_mut(game.phys.physics, 0.9, 0.5, 0.1)

	static_mesh.body = px.create_static(
		game.phys.physics,
		px.transform_new_1({0, 0, 0}),
		&geometry,
		phys_material,
		px.transform_new_1({0, 0, 0}),
	)
	assert(static_mesh.body != nil)

	px.scene_add_actor_mut(game.phys.scene, static_mesh.body, nil)

	static_mesh.mesh = gpu_mesh
	static_mesh.material = material
}
