import bindless;
import brdf;

float3 evaluate_specular_ibl(float3 r, float perceptualRoughness) {
    // This assumes a 256x256 cubemap, with 9 mip levels
    float lod = 7.0 * perceptualRoughness;
    return sample_cubemap(ENVIRONMENT_MAP_ID, r, lod).rgb;
}

// TODO: Load SH coefs.
float3 irradiance_sh(float3 n, float4 sh[9]) {    
    let x = -n.z;
    let y = n.x;
    let z = n.y;

    let color =
          sh[0].rgb
        + sh[1].rgb * (x)
        + sh[2].rgb * (y)
        + sh[3].rgb * (z)
        + sh[4].rgb * (x * z)
        + sh[5].rgb * (z * y)
        + sh[6].rgb * (y * x)
        + sh[7].rgb * (3.0 * z * z - 1.0)
        + sh[8].rgb * (x * x - y * y);

    return max(color, 0);
}

float3 sample_dfg(float NoV, float p_roughness) {
    let linear_roughness = p_roughness * p_roughness;
    return sample_texture(DFG_ID, float2(NoV, linear_roughness)).rgb;
}

float3 evaluate_ibl(float3 n, float3 v, float3 diffuse_color, float3 f0, float p_roughness, float4 sh[9]) {
    float NoV = max(dot(n, v), 0.0);
    float3 r = reflect(-v, n);

    float3 Lld = evaluate_specular_ibl(r, p_roughness);
    float2 Ldfg = sample_dfg(NoV, p_roughness).rg;
    float3 Lr = (f0 * Ldfg.x + Ldfg.y) * Lld;

    float3 diffuse_irradiance = irradiance_sh(n, sh);
    float3 Ld = diffuse_color * diffuse_irradiance;

    return Ld + Lr;
}
