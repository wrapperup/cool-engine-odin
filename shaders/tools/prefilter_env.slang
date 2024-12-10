import "../types";
import "../brdf";
import common;

#define PI 3.14159265359

static const u32 SAMPLE_COUNT = 1024;
static const u32 ROUGHNESS_LEVELS = 9;

[vk_binding(0, 0)] SamplerCube EnvironmentMap; // Base level
[vk_binding(1, 0)] RWTexture2DArray PrefilteredMap[ROUGHNESS_LEVELS]; // ROUGHNESS_LEVELS mips

struct PushConstants {
  u32 mip_level;
  u32 sample_count;
};

[vk_push_constant] PushConstants pc;

// z = face index
[numthreads(16, 16, 1)]
[shader("compute")]
void compute_main(Vec3u32 dispatchThreadID: SV_DispatchThreadID) {
  let texel_coord = Vec3i32(dispatchThreadID.xyz);

  Vec3u32 size;
  PrefilteredMap[0].GetDimensions(size.x, size.y, size.z);
  size.xy = size.xy >> pc.mip_level;

  if (texel_coord.x >= size.x || texel_coord.y >= size.y || texel_coord.z >= size.z) {
    return;
  }

  Vec3u32 coord = Vec3u32(texel_coord.x, size.y - texel_coord.y, texel_coord.z);
  float3 N = get_world_direction(coord, size.x);
  let V = N;

  float p_roughness = float(pc.mip_level) / float(ROUGHNESS_LEVELS - 1);

  float3 sum_prefilter = 0;
  float sum_NoL = 0;

  u32 i;
  for (i = 0; i < pc.sample_count; i++) {
    let Xi = hammersley(i, pc.sample_count);
    let H = importance_sample_ggx(Xi, N, p_roughness);
    let L  = normalize(2.0 * dot(V, H) * H - V);

    let NoL = max(dot(N, L), 0.0);
    if (NoL > 0.f) {
      sum_prefilter += clamp(EnvironmentMap.SampleLevel(L, pc.mip_level).rgb * NoL, 0.0, 10.0);
      sum_NoL += NoL;
    }
  }

  let prefiltered_color = sum_prefilter / sum_NoL;

  PrefilteredMap[pc.mip_level][texel_coord] = float4(prefiltered_color, 1.0);
}
