#define SHADOW_ID 0
#define A_ID 1
#define B_ID 2
#define C_ID 3
#define D_ID 4
#define E_ID 5
#define TONY_MC_MAPFACE_ID 6

[vk_binding(0, 0)] Texture2D Textures[];
[vk_binding(0, 0)] Texture2D<float4> TexturesHDR[];
[vk_binding(0, 0)] Texture2D<float> DepthTextures[];
[vk_binding(0, 0)] Texture3D<float3> LUTs[];

#define DEFAULT_SAMPLER_ID 0
#define SHADOW_SAMPLER_ID 1

[vk_binding(1, 0)] SamplerState Samplers[];
[vk_binding(1, 0)] SamplerComparisonState DepthSamplers[];

#define DRAW_IMAGE_ID 0

[vk_binding(2, 0)] RWTexture2D Images[];
[vk_binding(2, 0)] RWTexture2D<float4> HDRImages[];
[vk_binding(2, 0)] RWTexture2DMS ImagesMS[];
[vk_binding(2, 0)] RWTexture2DMS<float4> HDRImagesMS[];
