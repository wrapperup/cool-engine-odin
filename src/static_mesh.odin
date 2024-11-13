package game

import "gfx"

StaticMesh :: struct {
	using entity: ^Entity,
	mesh:         gfx.GPUMeshBuffers,
	material:     MaterialId,
}

init_static_mesh :: proc(static_mesh: ^StaticMesh, mesh_file_name: cstring, material: MaterialId) {
	mesh, ok := gfx.load_mesh_from_file(mesh_file_name)
	assert(ok)

	static_mesh.mesh = mesh
	static_mesh.material = material
}
