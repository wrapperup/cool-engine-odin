// Based on https://google.github.io/filament/Filament.md.html#materialsystem/standardmodel

import bindless;
import brdf;
import ibl;

float3 standard_brdf(float3 diffuse, float perceptual_roughness, float3 v, float3 l, float3 n, float3 h, float3 f0, float NoL) {
    float NoV = abs(dot(n, v)) + 1e-5;
    float NoH = clamp(dot(n, h), 0.0, 1.0);
    float LoH = clamp(dot(l, h), 0.0, 1.0);
    float VoH = clamp(dot(v, h), 0.0, 1.0);

    float linear_roughness = perceptual_roughness * perceptual_roughness;

    float  D = D_ggx(NoH, linear_roughness);
    float3 F = F_schlick(VoH, f0);
    float  V = V_smith_ggx_correlated(NoV, NoL, linear_roughness);

    // specular BRDF
    float3 Fr = (D * V) * F;

    // diffuse BRDF
    float3 Fd = diffuse * Fd_lambert();

    // let dfg = sample_dfg(NoV, linear_roughness);
    // let energyCompensation = 1.0 + f0 * (1.0 / dfg.g - 1.0);
    // Fr *= energyCompensation;

    // apply lighting...
    return Fd + Fr;
}
