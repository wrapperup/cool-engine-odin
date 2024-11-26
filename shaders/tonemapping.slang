#include "./bindless.slang"

float3 tony_mc_mapface(float3 stimulus) {
  // Apply a non-linear transform that the LUT is encoded with.
  const float3 encoded = stimulus / (stimulus + 1.0);

  // Align the encoded range to texel centers.
  const float LUT_DIMS = 48.0;
  float3 uv = encoded * ((LUT_DIMS - 1.0) / LUT_DIMS) + 0.5 / LUT_DIMS;

  // Note: for OpenGL, do `uv.y = 1.0 - uv.y`
  return sample_lut_3d(TONY_MC_MAPFACE_ID, uv);
}

[numthreads(16, 16, 1)]
[shader("compute")]
void compute_main(uint3 dispatchThreadID: SV_DispatchThreadID) {
  let texel_coord = uint2(dispatchThreadID.xy);

  uint2 size;
  HDRImages[RESOLVED_IMAGE_ID].GetDimensions(size.x, size.y);

  let exposure = 2.0f;
  if (texel_coord.x < size.x && texel_coord.y < size.y) {
    let hdr_color = HDRImages[RESOLVED_IMAGE_ID][texel_coord].rgb * exposure;
    let mapped = tony_mc_mapface(hdr_color);

    let gamma_corrected = float4(pow(mapped, float3(1.0/2.2)), 1.0);
    let linear_color = float4(mapped, 1.0);

    HDRImages[RESOLVED_IMAGE_ID][texel_coord] = gamma_corrected;
  }
}
