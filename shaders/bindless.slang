static const uint SHADOW_ID = 0;
static const uint TONY_MC_MAPFACE_ID = 1;
static const uint DFG_ID = 2;
static const uint ENVIRONMENT_MAP_ID = 3;

[vk_binding(0, 0)] Texture2D Textures[];
[vk_binding(0, 0)] Texture2D<float4> TexturesHDR[];
[vk_binding(0, 0)] Texture2D<float> DepthTextures[];
[vk_binding(0, 0)] Texture2D<float3> LUTs[];
[vk_binding(0, 0)] Texture3D<float3> LUTs3D[];
[vk_binding(0, 0)] TextureCube Cubemaps[];

static const uint DEFAULT_SAMPLER_ID = 0;
static const uint SHADOW_SAMPLER_ID = 1;
static const uint ENVIRONMENT_SAMPLER_ID = 2;

[vk_binding(1, 0)] SamplerState Samplers[];
[vk_binding(1, 0)] SamplerComparisonState DepthSamplers[];

static const uint RESOLVED_IMAGE_ID = 0;

[vk_binding(2, 0)] RWTexture2D Images[];
[vk_binding(2, 0)] RWTexture2D<float4> HDRImages[];
[vk_binding(2, 0)] RWTexture2DMS ImagesMS[];
[vk_binding(2, 0)] RWTexture2DMS<float4> HDRImagesMS[];

float4 sample_texture(uint id, float2 coord) {
    return Textures[id].Sample(Samplers[DEFAULT_SAMPLER_ID], coord);
}

float4 sample_hdr(uint id, float2 coord) {
    return TexturesHDR[id].Sample(Samplers[DEFAULT_SAMPLER_ID], coord);
}

float4 sample_depth(uint id, float2 coord) {
    return DepthTextures[id].Sample(Samplers[SHADOW_SAMPLER_ID], coord);
}

float3 sample_lut(uint id, float2 coord) {
    // Ensure we're sampling from lowest mip.
    return LUTs[id].SampleLevel(Samplers[DEFAULT_SAMPLER_ID], coord, 0);
}

float3 sample_lut_3d(uint id, float3 coord) {
    // Ensure we're sampling from lowest mip.
    return LUTs3D[id].SampleLevel(Samplers[DEFAULT_SAMPLER_ID], coord, 0);
}

float4 sample_cubemap(uint id, float3 coord) {
    return Cubemaps[id].Sample(Samplers[ENVIRONMENT_SAMPLER_ID], coord);
}

float4 sample_cubemap(uint id, float3 coord, float level) {
    return Cubemaps[id].SampleLevel(Samplers[ENVIRONMENT_SAMPLER_ID], coord, level);
}
