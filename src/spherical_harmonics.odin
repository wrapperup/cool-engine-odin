package game

import "core:strings"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"

import ktx "deps:odin-libktx"

@shader_shared
Sh_Coefficients :: struct {
    coeffs: [9]Vec4
}

process_sh_coefficients_from_cubemap_file :: proc(in_filename: string) -> Sh_Coefficients {
	buffer, size := load_image_into_bytes(in_filename)
	coeffs := process_sh_from_cubemap(buffer, size.x)

	return coeffs
}

process_sh_coefficients_from_equirectangular_file :: proc(in_filename: string, loc := #caller_location) -> Sh_Coefficients {
	buffer, size := load_image_into_bytes(in_filename, loc)
	coeffs := process_sh_from_equirectangular(buffer, size.x)

	return coeffs
}

CUBEMAP_FACE_NORMALS_TABLE: [6][3]Vec3 = {
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


process_sh_from_cubemap :: proc(faces: []Vec4, size: int) -> Sh_Coefficients {
	// Forsyth's weights
	weight1: f32 = 4.0 / 17.0
	weight2: f32 = 8.0 / 17.0
	weight3: f32 = 15.0 / 17.0
	weight4: f32 = 5.0 / 68.0
	weight5: f32 = 15.0 / 68.0

	sh: Sh_Coefficients

	weight_accum: f32 = 0.0

	cubemap_face_dirs: [dynamic][dynamic]Vec3
	reserve(&cubemap_face_dirs, 6)

	for i in 0 ..< 6 {
		face_dirs: [dynamic]Vec3
		reserve(&face_dirs, size * size)

		for v in 0 ..< size {
			for u in 0 ..< size {
				fu := (2.0 * f32(u) / (f32(size) - 1.0)) - 1.0
				fv := (2.0 * f32(v) / (f32(size) - 1.0)) - 1.0

				x := CUBEMAP_FACE_NORMALS_TABLE[i][0] * fu
				y := CUBEMAP_FACE_NORMALS_TABLE[i][1] * fv
				z := CUBEMAP_FACE_NORMALS_TABLE[i][2]

				tex_v := x + y + z
				tex_v = linalg.normalize(tex_v)

				append(&face_dirs, tex_v)
			}
		}
		append(&cubemap_face_dirs, face_dirs)
	}

	for i in 0 ..< 6 {
		for v in 0 ..< size {
			for u in 0 ..< size {
				color := faces[u + (v * size) + (i * size * size)].rgba

				tex_v := cubemap_face_dirs[i][u + (v * size)]

				weight := solid_angle_cubemap(f32(u), f32(v), f32(size))

				color *= weight

				sh.coeffs[0] += color * weight1

				sh.coeffs[1] += color * weight2 * tex_v.x
				sh.coeffs[2] += color * weight2 * tex_v.y
				sh.coeffs[3] += color * weight2 * tex_v.z

				sh.coeffs[4] += color * weight3 * tex_v.x * tex_v.z
				sh.coeffs[5] += color * weight3 * tex_v.z * tex_v.y
				sh.coeffs[6] += color * weight3 * tex_v.y * tex_v.x
				sh.coeffs[7] += color * weight4 * (3.0 * tex_v.z * tex_v.z - 1.0)
				sh.coeffs[8] += color * weight5 * (tex_v.x * tex_v.x - tex_v.y * tex_v.y)

				weight_accum += weight * 3.0
			}
		}
	}

	sh.coeffs *= 4.0 * math.PI / weight_accum

	return sh
}

process_sh_from_equirectangular :: proc(equirectangular: []Vec4, width: int) -> Sh_Coefficients {
	// Forsyth's weights
	weight1: f32 = 4.0 / 17.0
	weight2: f32 = 8.0 / 17.0
	weight3: f32 = 15.0 / 17.0
	weight4: f32 = 5.0 / 68.0
	weight5: f32 = 15.0 / 68.0

	sh: Sh_Coefficients

	weight_accum: f32 = 0.0

	height := len(equirectangular) / width

	for v in 0 ..< height {
		for u in 0 ..< width {
			fu := f32(v) / f32(height)
			fv := f32(u) / f32(width)

			latitude := (1 - fv) * math.PI - (math.PI / 2)
			longitude := fu * (2 * math.PI) - math.PI

			x := -math.cos(latitude) * math.cos(longitude)
			y := -math.sin(latitude)
			z := -math.cos(latitude) * math.sin(longitude)

			tex_v := linalg.normalize(Vec3{x, y, z})

			color := equirectangular[u + (v * width)].rgba

			solid_angle_equirectangular :: proc(v, w, h: f32) -> f32 {
				delta_phi := 2 * math.PI / w
				delta_theta := math.PI / h

				theta := v * math.PI

				solid_angle := delta_phi * delta_theta * math.sin(theta)
				return solid_angle
			}

			weight := solid_angle_equirectangular(fv, f32(width), f32(height))

			color *= weight

			sh.coeffs[0] += color * weight1

			sh.coeffs[1] += color * weight2 * tex_v.x
			sh.coeffs[2] += color * weight2 * tex_v.y
			sh.coeffs[3] += color * weight2 * tex_v.z

			sh.coeffs[4] += color * weight3 * tex_v.x * tex_v.z
			sh.coeffs[5] += color * weight3 * tex_v.z * tex_v.y
			sh.coeffs[6] += color * weight3 * tex_v.y * tex_v.x
			sh.coeffs[7] += color * weight4 * (3.0 * tex_v.z * tex_v.z - 1.0)
			sh.coeffs[8] += color * weight5 * (tex_v.x * tex_v.x - tex_v.y * tex_v.y)

			weight_accum += weight * 3.0
		}
	}

	sh.coeffs *= 4.0 * math.PI / weight_accum

	return sh
}

// Explanation: https://www.rorydriscoll.com/2012/01/15/cubemap-texel-solid-angle/
solid_angle_cubemap :: proc(au: f32, av: f32, size: f32) -> f32 {
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

load_image_into_bytes :: proc(filename: string, loc := #caller_location) -> ([]Vec4, [2]int) {
	ktx_texture: ^ktx.Texture2
    filename_c := strings.clone_to_cstring(filename)
    defer delete(filename_c)
	ktx_result := ktx.Texture2_CreateFromNamedFile(filename_c, {.TEXTURE_CREATE_LOAD_IMAGE_DATA}, &ktx_texture)
	assert(ktx_result == .SUCCESS, "Failed to load image.", loc)

	is_compressed := ktx_texture.isCompressed
	assert(!is_compressed)

	size := ktx.Texture_GetDataSize(ktx_texture)
	data := ktx.Texture_GetData(ktx_texture)
	format := ktx.Texture_GetVkFormat(ktx_texture)

	// For now... I wonder if we can have this converted automatically for us.
	assert(format == .R32G32B32A32_SFLOAT)

	buffer := make_slice([]u8, size)

	mem.copy(&buffer[0], data, int(size))

	return slice.reinterpret([]Vec4, buffer), {int(ktx_texture.baseWidth), int(ktx_texture.baseHeight)}
}
