#define SHADOW_ID 0
#define A_ID 1
#define B_ID 2
#define C_ID 3
#define D_ID 4
#define E_ID 5

[vk_binding(0, 0)] Texture2D Textures[];
[vk_binding(0, 0)] Texture2D<float> DepthTextures[];

#define DEFAULT_SAMPLER_ID 0
#define SHADOW_SAMPLER_ID 1

[vk_binding(1, 0)] SamplerState Samplers[];
[vk_binding(1, 0)] SamplerComparisonState DepthSamplers[];
