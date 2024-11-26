import "../brdf";

// https://google.github.io/filament/Filament.md.html#toc9.5
float G_dfg(float NoV, float NoL, float a) {
	let a2 = a * a;
	let GGXL = NoV * sqrt((-NoL * a2 + NoL) * NoL + a2);
	let GGXV = NoL * sqrt((-NoV * a2 + NoV) * NoV + a2);
	return (2 * NoL) / (GGXV + GGXL);
}


// Calculates DFG1 and DFG2 terms. If `multiscatter` is enabled, the terms for the
// multiscatter integration will be generated instead.
//
// Normal integration: https://google.github.io/filament/Filament.md.html#toc9.5
// Multiscattering integration: https://google.github.io/filament/Filament.md.html#toc5.3.4.7
float2 dfg(float NoV, float linear_roughness, int sample_count, bool multiscatter = false) {
	// Construct `v` term from NoV for the approximation
	float3 V;
	V.x = sqrt(1.0 - NoV * NoV);
	V.y = 0.0;
	V.z = NoV;

	float2 r = 0;
	for (uint i = 0; i < sample_count; i++) {
		float2 Xi = hammersley(i, float(sample_count));
		float3 H = hemisphere_importance_sample_ggx(Xi, linear_roughness);
		float3 L = 2.0 * dot(V, H) * H - V;

		float VoH = saturate(dot(V, H));
		float NoL = saturate(L.z);
		float NoH = saturate(H.z);

		if (NoL > 0.0) {
			float G = G_dfg(NoV, NoL, linear_roughness);
			float Gv = G * VoH / NoH;
			float Fc = pow(1 - VoH, 5.0);

			if (multiscatter) {
				r.x += Gv * Fc;
				r.y += Gv;
			} else {
				r.x += Gv * (1 - Fc);
				r.y += Gv * Fc;
			}
		}
	}

	return r * (1.0 / float(sample_count));
}

[vk_binding(0, 0)] RWTexture2D<float2> DfgTexture;

[vk_push_constant] struct DfgPushConstant {
    uint32_t sample_count;
    bool multiscatter;
} pc;

// Integrates DFG into a f16 sequence that can be stored in a texture.
// Recommended to store this in a R16G16_SFLOAT texture.
[numthreads(16, 16, 1)]
[shader("compute")]
void compute_main(uint3 dispatchThreadID: SV_DispatchThreadID) {
    let texel_coord = uint2(dispatchThreadID.xy);

    uint width;
    uint height;
    uint levels;
    DfgTexture.GetDimensions(0, width, height, levels);

    let x = texel_coord.x;
    let y = texel_coord.y;

    let h = float(height);
    let coord = saturate((h - float(y) + 0.5) / h);
    let linear_roughness = coord * coord;

    let NoV = saturate((float(x) + 0.5) / float(width));
    let r = dfg(NoV, linear_roughness, 1024, pc.multiscatter);

    DfgTexture[texel_coord] = r;
}
