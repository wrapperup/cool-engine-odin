import bindless;
import common;
import types;

[vk_push_constant]
DDGIDebugAtlasPush pc;

// Shows the raw irradiance atlas stretched across the screen: a grid of octahedral
// probe tiles. Reinhard + gamma so HDR stays viewable.
[numthreads(16, 16, 1)]
[shader("compute")]
void compute_main(Vec3u32 dispatchThreadID: SV_DispatchThreadID) {
  let px = Vec2u32(dispatchThreadID.xy);
  uint2 size;
  pc.out_image.get_dimensions(size.x, size.y);
  if (px.x >= size.x || px.y >= size.y) {
    return;
  }

  let v = pc.volume;
  let uv = (Vec2(px) + 0.5) / Vec2(size);
  let c = v.irradiance.sample_level(v.sampler, uv, 0).rgb;

  let mapped = c / (c + 1.0);
  pc.out_image.store(px, Vec4(pow(mapped, Vec3(1.0 / 2.2)), 1.0));
}
