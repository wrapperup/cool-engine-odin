import bindless;

// 9 imad (+ 6 iops with final shuffle) -- https://vkguide.dev
uint3 pcg_3d(uint3 v) {

  v = v * 1664525u + 1013904223u;

  v.x += v.y * v.z;
  v.y += v.z * v.x;
  v.z += v.x * v.y;

  v ^= v >> 16u;

  v.x += v.y * v.z;
  v.y += v.z * v.x;
  v.z += v.x * v.y;

  return v;
}

float shadow_calc(float4 shadow_coord, float2 offset = 0.0, float bias) {
  // perform perspective divide
  float3 proj_coords = shadow_coord.xyz / shadow_coord.w;

  let shadow = DepthTextures[SHADOW_ID].SampleCmpLevelZero(
      DepthSamplers[SHADOW_SAMPLER_ID], proj_coords.xy + offset,
      proj_coords.z - bias);

  return shadow;
}

float filter_pcf(float2 screen_pos, float4 shadow_coord, float bias) {
  int2 texDim;
  DepthTextures[SHADOW_ID].GetDimensions(texDim.x, texDim.y);

  float scale = 1.5;
  float dx = scale * 1.0 / float(texDim.x);
  float dy = scale * 1.0 / float(texDim.y);

  float shadow_factor = 0.0;
  int count = 0;
  int range = 2;

  float3 proj_coords = shadow_coord.xyz / shadow_coord.w;

  proj_coords = proj_coords;

  uint4 u = uint4(uint2(screen_pos), uint(screen_pos.x) ^ uint(screen_pos.y),
                  uint(screen_pos.x) + uint(screen_pos.y));
  float3 rand = pcg_3d(u.xyz);
  rand = normalize(rand);

  float2 dirA = normalize(rand.xy);
  float2 dirB = normalize(float2(-dirA.y, dirA.x));

  dirA *= dx;
  dirB *= dy;

  float current_depth = proj_coords.z;

  for (int x = -range; x <= range; x++) {
    for (int y = -range; y <= range; y++) {
      shadow_factor += shadow_calc(shadow_coord, dirA * x + dirB * y, bias);
      count++;
    }
  }

  return shadow_factor / count;
}
