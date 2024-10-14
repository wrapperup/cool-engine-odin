import brdf;

static const uint SAMPLE_COUNT = 1024;
static const uint ROUGHNESS_LEVELS = 9;

[vk_binding(0, 0)] SamplerCube EnvironmentMap; // Base level
[vk_binding(0, 1)] RWTexture2DArray PrefilteredMap[ROUGHNESS_LEVELS]; // ROUGHNESS_LEVELS mips

// z = face index
[numthreads(16, 16, 1)]
[shader("compute")]
void main(uint3 dispatchThreadID: SV_DispatchThreadID) {
    let texel_coord = uint2(dispatchThreadID.xy);

    printf("Hello from compute shader!");
}
