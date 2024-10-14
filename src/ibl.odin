package main

import "core:os"

import "core:math"
import "core:math/linalg"
import vk "vendor:vulkan"

import "./gfx"

// https://google.github.io/filament/Filament.md.html#toc9.4
hammersley :: proc(i: uint, numSamples: f32) -> [2]f32 {
	using math
	bits := i
	bits = (bits << 16) | (bits >> 16)
	bits = ((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1)
	bits = ((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2)
	bits = ((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4)
	bits = ((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8)
	return {f32(i) / numSamples, f32(bits) / pow_f32(2, 32)}
}

D_importance_sample_ggx :: proc(u: [2]f32, a: f32) -> [3]f32 {
	using math

	phi := 2.0 * f32(math.PI) * u.x
	// NOTE: (aa-1) == (a-1)(a+1) produces better fp accuracy
	cosTheta2 := (1 - u.y) / (1 + (a + 1) * ((a - 1) * u.y))
	cosTheta := sqrt(cosTheta2)
	sinTheta := sqrt(1 - cosTheta2)
	return {sinTheta * cos(phi), sinTheta * sin(phi), cosTheta}
}

// https://google.github.io/filament/Filament.md.html#toc9.5
G_dfg :: proc(NoV, NoL, a: f32) -> f32 {
	using math
	a2 := a * a
	GGXL := NoV * sqrt((-NoL * a2 + NoL) * NoL + a2)
	GGXV := NoL * sqrt((-NoV * a2 + NoV) * NoV + a2)
	return (2 * NoL) / (GGXV + GGXL)
}

// Calculates DFG1 and DFG2 terms. If `multiscatter` is enabled, the terms for the
// multiscatter integration will be generated instead.
//
// Normal integration: https://google.github.io/filament/Filament.md.html#toc9.5
// Multiscattering integration: https://google.github.io/filament/Filament.md.html#toc5.3.4.7
dfg :: proc(NoV, linear_roughness: f32, sample_count: int, multiscatter: bool = false) -> [2]f32 {
	using math

	// Construct `v` term from NoV for the approximation
	V: [3]f32
	V.x = sqrt(1.0 - NoV * NoV)
	V.y = 0.0
	V.z = NoV

	r: [2]f32 = 0
	for i in 0 ..< sample_count {
		Xi := hammersley(uint(i), f32(sample_count))
		H := D_importance_sample_ggx(Xi, linear_roughness)
		L := 2.0 * linalg.dot(V, H) * H - V

		VoH := saturate(linalg.dot(V, H))
		NoL := saturate(L.z)
		NoH := saturate(H.z)

		if (NoL > 0.0) {
			G := G_dfg(NoV, NoL, linear_roughness)
			Gv := G * VoH / NoH
			Fc := pow(1 - VoH, 5.0)

			if multiscatter {
				r.x += Gv * Fc
				r.y += Gv
			} else {
				r.x += Gv * (1 - Fc)
				r.y += Gv * Fc
			}
		}
	}
	return r * (1.0 / f32(sample_count))
}

// Integrates DFG into a f32 byte sequence that can be stored in a texture.
// Recommended to use compute_dfg_lut_f16 instead.
// Expensive! Only use this for pre-calculating the DFG terms
compute_dfg_lut_f32 :: proc(out_dfg: [][2]f32, width, height: u32, multiscatter: bool = false) {
	using math

	for y in 0 ..< height {
		h := f32(height)
		coord := saturate((h - f32(y) + 0.5) / h)
		linear_roughness := coord * coord

		for x in 0 ..< width {
			NoV := saturate((f32(x) + 0.5) / f32(width))
			r := dfg(NoV, linear_roughness, 1024, multiscatter)
			out_dfg[x * (y * width)] = r
		}
	}
}

// Integrates DFG into a f16 sequence that can be stored in a texture.
// Recommended to store this in a R16G16_SFLOAT texture.
// Expensive! Only use this for pre-calculating the DFG terms
compute_dfg_lut_f16 :: proc(out_dfg: [][2]f16, width, height: u32, multiscatter: bool = false) {
	using math

	for y in 0 ..< height {
		h := f32(height)
		coord := saturate((h - f32(y) + 0.5) / h)
		linear_roughness := coord * coord

		for x in 0 ..< width {
			NoV := saturate((f32(x) + 0.5) / f32(width))
			r := dfg(NoV, linear_roughness, 1024, multiscatter)
			out_dfg[x + (y * width)] = {cast(f16)r.r, cast(f16)r.g}
		}
	}
}

