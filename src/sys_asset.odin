package game

AssetType :: enum {
	Sound,
	Mesh,
	SkinnedMesh,
}

UUID :: int

Asset :: struct {
	id:          UUID,
	source_path: string,
	type:        AssetType,
}

AssetSystem :: struct {
	assets:      map[UUID]Asset,
}

load_asset :: proc() {
}

get_asset :: proc(id: UUID) -> ^Asset {
	return &game.asset_system.assets[id]
}
