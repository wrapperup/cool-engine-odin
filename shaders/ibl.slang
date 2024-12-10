import bindless;
import brdf;
import common;
import consts;
import types;

Vec3 evaluate_specular_ibl(Vec3 r, f32 perceptualRoughness) {
    // This assumes a 256x256 cubemap, with 9 mip levels
    let lod = 8.0 * perceptualRoughness;
    return ENVIRONMENT_MAP_ID.sample_level(ENVIRONMENT_SAMPLER_ID, r, lod).rgb;
}

Vec3 irradiance_sh(Vec3 n, ShCoefficients sh) {    
    let x = -n.z;
    let y = n.x;
    let z = n.y;

    let color =
          sh.coeffs[0].rgb
        + sh.coeffs[1].rgb * (x)
        + sh.coeffs[2].rgb * (y)
        + sh.coeffs[3].rgb * (z)
        + sh.coeffs[4].rgb * (x * z)
        + sh.coeffs[5].rgb * (z * y)
        + sh.coeffs[6].rgb * (y * x)
        + sh.coeffs[7].rgb * (3.0 * z * z - 1.0)
        + sh.coeffs[8].rgb * (x * x - y * y);

    return max(color, 0);
}

/**
Vec3 irradiance_sh_volume(Vec3 position, Vec3 n, ShCoefficients *volume, Mat4x4 world_to_volume, uint3 size) {    
    let pos = mul(world_to_volume, Vec4(position, 0.f));
        
    let Ld = irradiance_sh(n, volume[clamp(index, 0, 242)]);

    return Ld;
}
*/

Vec3 sample_dfg(f32 NoV, f32 p_roughness) {
    let linear_roughness = p_roughness * p_roughness;
    return DFG_ID.sample(DEFAULT_SAMPLER_ID, Vec2(NoV, linear_roughness)).rgb;
}

Vec3 evaluate_ibl(Vec3 n, Vec3 v, Vec3 diffuse_color, Vec3 f0, f32 p_roughness, ShCoefficients sh) {
    let NoV = max(dot(n, v), 0.0);
    let r = reflect(-v, n);

    let Lld = evaluate_specular_ibl(r, p_roughness);
    let Ldfg = sample_dfg(NoV, p_roughness).rg;
    let Lr = (f0 * Ldfg.r + Ldfg.g) * Lld;

    let diffuse_irradiance = irradiance_sh(n, sh);
    let Ld = diffuse_color * diffuse_irradiance;

    return Ld + Lr;
}
