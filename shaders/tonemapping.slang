import bindless;
import common;
import types;

Vec3 tony_mc_mapface(Vec3 stimulus) {
  // Apply a non-linear transform that the LUT is encoded with.
  const Vec3 encoded = stimulus / (stimulus + 1.0);

  // Align the encoded range to texel centers.
  const f32 LUT_DIMS = 48.0;
  Vec3 uv = encoded * ((LUT_DIMS - 1.0) / LUT_DIMS) + 0.5 / LUT_DIMS;

  // Note: for OpenGL, do `uv.y = 1.0 - uv.y`
  return pc.tony_mc_mapface.sample_level(pc.sampler, uv, 0);
}

[vk_push_constant]
PostProcessingPushConstants pc;

[numthreads(16, 16, 1)]
[shader("compute")]
void compute_main(Vec3u32 dispatchThreadID: SV_DispatchThreadID) {
  let texel_coord = Vec2u32(dispatchThreadID.xy);

  uint2 size;
  pc.resolved_image.get_dimensions(size.x, size.y);

  let exposure = 3.0f;
  if (texel_coord.x < size.x && texel_coord.y < size.y) {
    let hdr_color = pc.resolved_image.load(texel_coord).rgb * exposure;
    let mapped = tony_mc_mapface(hdr_color);

    let gamma_corrected = Vec4(pow(mapped, Vec3(1.0/2.2)), 1.0);
    let linear_color = Vec4(mapped, 1.0);

    pc.resolved_image.store(texel_coord, gamma_corrected);
  }
}
