package game

AssetType :: enum {
	Sound,
	Mesh,
	SkinnedMesh,
}

Asset :: struct {
	id:          string, // TODO: Make this uuid?
	source_path: string,
	type:        AssetType,
}

AssetManager :: struct {
	assets: map[string]Asset, // TODO: UUID? This is path for now.
}

g_asset_manager: ^AssetManager

init_asset_manager :: proc() -> ^AssetManager {
	g_asset_manager = new(AssetManager)

	return g_asset_manager
}

set_asset_manager :: proc(asset_manager: ^AssetManager) {
	g_asset_manager = asset_manager
}

load_asset :: proc() {
}

get_asset :: proc(path: string) -> ^Asset {
    return &g_asset_manager.assets[path]
}
