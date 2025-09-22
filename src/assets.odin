package game

import "core:path/filepath"
import "core:strings"
import os "core:os/os2"

Asset_Type :: enum {
    Unknown,
	Text,
	Sound,
	Texture,
	Mesh,
	SkinnedMesh,
	Font,
}

// TODO:
// Asset_Meta :: struct {}

Asset :: struct {
	source_path: string,
	content:     []u8,
    // meta:        Asset_Meta,
	type:        Asset_Type,
}

asset_type_from_base :: proc(base: string) -> Asset_Type {
    asset_type := Asset_Type.Unknown

    switch filepath.ext(base) {
    case "wav":
        asset_type = .Sound
    case "txt":
        asset_type = .Text
    case "glb":
        if strings.starts_with(base, "sk") {
            asset_type = .SkinnedMesh
        } else {
            asset_type = .Mesh
        }
    case "ktx2":
        asset_type = .Texture
    case "ttf":
        asset_type = .Font
    }

    return asset_type
}


load_asset :: proc(path: string) -> (asset: Asset, ok: bool) {
    fullpath, fullpath_err := os.get_absolute_path(path, context.allocator)
    assert(fullpath_err == nil, "Failed to get absolute path")

    content, content_err := os.read_entire_file(path, context.allocator)
    assert(content_err == nil, "Could not read file contents")

    base := filepath.base(path)

    asset_type := asset_type_from_base(base)

    asset = {
        type = asset_type,
        content = content,
        source_path = fullpath,
    }

    ok = true

    return
}

get_asset :: proc(name: Asset_Name) -> ^Asset {
    return &asset_map[name]
}

asset_content :: proc(name: Asset_Name) -> []u8 {
    return asset_map[name].content
}

asset_path :: proc(name: Asset_Name) -> string {
    return asset_map[name].source_path
}
