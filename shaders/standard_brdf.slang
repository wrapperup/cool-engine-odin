// Based on https://google.github.io/filament/Filament.md.html#materialsystem/standardmodel

import bindless;
import brdf;
import ibl;
import types;

Vec3 standard_bsdf(Vec3 diffuse, float perceptual_roughness, Vec3 v, Vec3 l, Vec3 n, Vec3 h, Vec3 f0, Vec3 f90, f32 NoL) {
    float NoV = abs(dot(n, v)) + 1e-5;
    float NoH = clamp(dot(n, h), 0.0, 1.0);
    float LoH = clamp(dot(l, h), 0.0, 1.0);
    float VoH = clamp(dot(v, h), 0.0, 1.0);

    float linear_roughness = perceptual_roughness * perceptual_roughness;

    float  D = D_ggx(NoH, linear_roughness);
    Vec3 F = F_schlick(f0, f90, VoH);
    float  V = V_smith_ggx_correlated(NoV, NoL, linear_roughness);

    // specular BRDF
    Vec3 Fr = (D * V) * F;

    // diffuse BRDF
    Vec3 Fd = diffuse * Fd_lambert();

    // let dfg = sample_dfg(NoV, linear_roughness);
    // let energyCompensation = 1.0 + f0 * (1.0 / dfg.g - 1.0);
    // Fr *= energyCompensation;

    // apply lighting...
    return Fd + Fr;
}
