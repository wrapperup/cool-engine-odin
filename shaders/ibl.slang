import bindless;
import brdf;

float3 evaluate_specular_ibl(float3 r, float perceptualRoughness) {
    // This assumes a 256x256 cubemap, with 9 mip levels
    float lod = 8.0 * perceptualRoughness;
    return sample_cubemap(TEST_ENVIRONMENT_MAP_ID, r, uint(lod)).rgb;
}

// TODO: Load SH coefs.
float3 irradiance_sh(float3 n) {    
    // let sh0 = float3(  0.000000000039282561,  0.000000000039282561,  0.000000000039282561 );
    // let sh1 = float3(  0.000000037394376673,  0.000000037394376673,  0.000000037394376673 );
    // let sh2 = float3(  0.000000000013438193,  0.000000000013438193,  0.000000000013438193 );
    // let sh3 = float3(  0.000000131871997738,  0.000000131871997738,  0.000000131871997738 );
    // let sh4 = float3( -0.000006552605484689, -0.000006552605484689, -0.000006552605484689 );
    // let sh5 = float3( -0.000000255449261422, -0.000000255449261422, -0.000000255449261422 );
    // let sh6 = float3( -0.000000000047837879, -0.000000000047837879, -0.000000000047837879 );
    // let sh7 = float3(  0.000000096537610113,  0.000000096537610113,  0.000000096537610113 );
    // let sh8 = float3( -0.000005539932218752, -0.000005539932218752, -0.000005539932218752 );


    let sh0 = float3(0.48503733, 0.48316428, 0.32759333);
    let sh1 = float3(-0.26511002, 0.2617326, -0.0001285886);
    let sh2 = float3(-0.26024902, -0.26002043, 0.26548815);
    let sh3 = float3(0.2476333, 0.24728885, 0.24757174);
    let sh4 = float3(0.00032010232, 0.00019238597, 0.0005412985);
    let sh5 = float3(0.0009668731, 0.0009325959, 0.00018943335);
    let sh6 = float3(-0.00040348107, -0.00046164956, 0.00018102766);
    let sh7 = float3(0.0044354284, 0.0049572727, 0.030710248);
    let sh8 = float3(0.002222224, 0.000540525, -0.08147548);
    
    let z = n.z;
    let x = n.x;
    let y = n.y;

    return
          sh0
        + sh1 * (x)
        + sh2 * (y)
        + sh3 * (z)
        + sh4 * (x * z)
        + sh5 * (z * y)
        + sh6 * (y * x)
        + sh7 * (3.0 * z * z - 1.0)
        + sh8 * (x * x - y * y);
}

float3 sample_dfg(float NoV, float linear_roughness) {
    return sample_texture(DFG_ID, float2(NoV, linear_roughness)).rgb;
}

float3 evaluate_ibl(float3 n, float3 v, float3 diffuse_color, float3 f0, float3 f90, float perceptual_roughness) {
    float NoV = max(dot(n, v), 0.0);
    float3 r = reflect(-v, n);

    float3 Ld = irradiance_sh(n);

    float3 Lld = evaluate_specular_ibl(r, perceptual_roughness);
    float2 Ldfg = sample_dfg(NoV, perceptual_roughness).rg;
    float3 Lr = (f0 * Ldfg.x + f90 * Ldfg.y) * Lld;

    return Ld + Lr;
}
