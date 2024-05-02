package main

PackedVoxelData :: distinct u8

encode_voxel_data :: proc(iso: u8) -> PackedVoxelData {
    return PackedVoxelData(iso)
}
