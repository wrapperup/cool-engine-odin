package game

import "core:flags"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:sys/windows"
import "core:time"

import vk "vendor:vulkan"

import "../src/gfx"
import ktx "deps:odin-libktx"
import vma "deps:odin-vma"

import impl "../src"

process_sh_coefficients_from_file :: proc(in_filename: cstring) -> [9][3]f32 {
	fmt.println("Generating SH coefficients...")

	buffer, size := load_cubemap_into_bytes(in_filename)
	coeffs := process(buffer, size)

	return coeffs
}

CUBEMAP_FACE_NORMALS_TABLE: [6][3][3]f32 = {
	{
		// +x
		{0.0, 0.0, -1.0},
		{0.0, -1.0, 0.0},
		{1.0, 0.0, 0.0},
	},
	{
		// -x
		{0.0, 0.0, 1.0},
		{0.0, -1.0, 0.0},
		{-1.0, 0.0, 0.0},
	},
	{
		// +y
		{1.0, 0.0, 0.0},
		{0.0, 0.0, 1.0},
		{0.0, 1.0, 0.0},
	},
	{
		// -y
		{1.0, 0.0, 0.0},
		{0.0, 0.0, -1.0},
		{0.0, -1.0, 0.0},
	},
	{
		// +z
		{1.0, 0.0, 0.0},
		{0.0, -1.0, 0.0},
		{0.0, 0.0, 1.0},
	},
	{
		// -z
		{-1.0, 0.0, 0.0},
		{0.0, -1.0, 0.0},
		{0.0, 0.0, -1.0},
	},
}


process :: proc(faces: [][4]f32, size: int) -> [9][3]f32 {
	// Forsyth's weights
	weight1: f32 = 4.0 / 17.0
	weight2: f32 = 8.0 / 17.0
	weight3: f32 = 15.0 / 17.0
	weight4: f32 = 5.0 / 68.0
	weight5: f32 = 15.0 / 68.0

	sh: [9][3]f32

	weight_accum: f32 = 0.0

	for i in 0 ..< 6 {
		for v in 0 ..< size {
			for u in 0 ..< size {
				fu := (2.0 * f32(u) / (f32(size) - 1.0)) - 1.0
				fv := (2.0 * f32(v) / (f32(size) - 1.0)) - 1.0

				x := CUBEMAP_FACE_NORMALS_TABLE[i][0] * fu
				y := CUBEMAP_FACE_NORMALS_TABLE[i][1] * fv
				z := CUBEMAP_FACE_NORMALS_TABLE[i][2]

				tex_v := x + y + z

				color := faces[u + (v * size) + (i * size * size)].rgb

				weight := solid_angle(f32(u), f32(v), f32(size))

				color *= weight

				sh[0] += color * weight1

				sh[1] += color * weight2 * tex_v.x
				sh[2] += color * weight2 * tex_v.y
				sh[3] += color * weight2 * tex_v.z

				sh[4] += color * weight3 * tex_v.x * tex_v.z
				sh[5] += color * weight3 * tex_v.z * tex_v.y
				sh[6] += color * weight3 * tex_v.y * tex_v.x
				sh[7] += color * weight4 * (3.0 * tex_v.z * tex_v.z - 1.0)
				sh[8] += color * weight5 * (tex_v.x * tex_v.x - tex_v.y * tex_v.y)

				weight_accum += weight * 3.0
			}
		}
	}

	sh *= 4.0 * math.PI / weight_accum

	return sh
}

// Explanation: https://www.rorydriscoll.com/2012/01/15/cubemap-texel-solid-angle/
solid_angle :: proc(au: f32, av: f32, size: f32) -> f32 {
	u := (2.0 * (au + 0.5) / size) - 1.0
	v := (2.0 * (av + 0.5) / size) - 1.0

	inv_size := 1.0 / size

	// U and V are the -1..1 texture coordinate on the current face.
	// get projected area for this texel
	x0 := u - inv_size
	y0 := v - inv_size
	x1 := u + inv_size
	y1 := v + inv_size
	angle := area_element(x0, y0) - area_element(x0, y1) - area_element(x1, y0) + area_element(x1, y1)

	return angle
}

area_element :: proc(x, y: f32) -> f32 {
	return math.atan2(x * y, math.sqrt(x * x + y * y + 1.0))
}

load_cubemap_into_bytes :: proc(filename: cstring) -> ([][4]f32, int) {
	ktx_texture: ^ktx.Texture2
	ktx_result := ktx.Texture2_CreateFromNamedFile(filename, {.TEXTURE_CREATE_LOAD_IMAGE_DATA}, &ktx_texture)
	assert(ktx_result == .SUCCESS, "Failed to load image.")

	is_cubemap := ktx_texture.isCubemap
	is_compressed := ktx_texture.isCompressed
	assert(is_cubemap)
	assert(!is_compressed)

	size := ktx.Texture_GetDataSize(ktx_texture)
	data := ktx.Texture_GetData(ktx_texture)
	format := ktx.Texture_GetVkFormat(ktx_texture)
	face_size := size_of(f32) * 4 * ktx.Texture_GetImageSize(ktx_texture, 0)

	// For now... I wonder if we can have this converted automatically for us.
	assert(format == .R32G32B32A32_SFLOAT)

	buffer := make_slice([]u8, size)

	mem.copy(&buffer[0], data, int(size))

	return slice.reinterpret([][4]f32, buffer), int(ktx_texture.baseWidth)
}
