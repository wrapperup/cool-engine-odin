import bindless;
import brdf;
import common;
import types;

struct PBR_Params {
    ImageCube env_map;
    Image2D dfg;
    Sampler env_sampler;
    Sampler default_sampler;
}

Vec3 evaluate_specular_ibl(PBR_Params params, Vec3 r, f32 perceptualRoughness) {
    // This assumes a 256x256 cubemap, with 9 mip levels
    let lod = 8.0 * perceptualRoughness;
    return params.env_map.sample_level(params.env_sampler, r, lod).rgb;
}

Vec3 irradiance_sh(Vec3 n, Sh_Coefficients sh) {    
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

Vec3 irradiance_sh_volume(Vec3 position, Vec3 n, Sh_Coefficients *volume, Mat4x4 world_to_volume) {    
    let pos = mul(world_to_volume, Vec4(position, 0.f));
    u32 index = u32(pos.x) + u32(pos.y * 9) + u32(pos.z * 3);

    let Ld = irradiance_sh(n, volume[clamp(index, 0, 242)]);

    return Ld;
}

Vec3 sample_dfg(PBR_Params params, f32 NoV, f32 p_roughness) {
    let linear_roughness = p_roughness * p_roughness;
    return params.dfg.sample(params.default_sampler, Vec2(NoV, linear_roughness)).rgb;
}

Vec3 evaluate_ibl(PBR_Params params, Vec3 n, Vec3 v, Vec3 diffuse_color, Vec3 f0, f32 p_roughness, Sh_Coefficients *volume, Vec3 coord, Mat4x4 world_to_volume) {
    let f90 = saturate(dot(f0, Vec3(50.0 * 0.33)));

    let NoV = max(dot(n, v), 0.0);
    let r = reflect(-v, n);

    let Lld = evaluate_specular_ibl(params, r, p_roughness);
    let Ldfg = sample_dfg(params, NoV, p_roughness).rg;

#ifdef MULTISCATTERING
    let Lr = lerp(Ldfg.xxx, Ldfg.yyy, f0);
#else
    // TODO: FIX: This is absolutety wrong, but the DFG2 term seems way too harsh...
    let Lr = (f0 * Ldfg.r + f90 * Ldfg.g) * Lld;
#endif

    let diffuse_irradiance = irradiance_sh_volume(coord, n, volume, world_to_volume);
    let Ld = diffuse_color * diffuse_irradiance;

    return Lr + Ld;
}
