import bindless;
import common;
import types;
import rt_common;

[vk_push_constant]
DebugRTPushConstants pc;

// One ray per pixel against the scene TLAS. On a hit, the geometry table resolves the
// instance back to its vertex/index buffers + material; albedo (texture * vertex color)
// is lit with sun NoL + point lights + sky ambient using the normal-mapped normal.
// Reinhard + gamma keeps the un-tonemapped output viewable. Miss = dark.
[numthreads(16, 16, 1)]
[shader("compute")]
void compute_main(Vec3u32 dispatchThreadID: SV_DispatchThreadID) {
  let px = Vec2u32(dispatchThreadID.xy);

  uint2 size;
  pc.out_image.get_dimensions(size.x, size.y);
  if (px.x >= size.x || px.y >= size.y) {
    return;
  }

  let g = pc.global;

  // Pixel center -> NDC. Vulkan clip-space y points down, matching texel y.
  let uv = (Vec2(px) + 0.5) / Vec2(size);
  let ndc = uv * 2.0 - 1.0;

  // Infinite-far projection: NDC z=1 is at infinity (w->0). Unproject finite depths
  // only and build the ray from two points on it.
  let p_near = mul(g.clip_to_world, Vec4(ndc, 0.0, 1.0));
  let p_mid = mul(g.clip_to_world, Vec4(ndc, 0.5, 1.0));
  let origin = p_near.xyz / p_near.w;
  let dir = normalize(p_mid.xyz / p_mid.w - origin);

  let s = rt_trace_surface_detailed(pc.tlas.get(), pc.geometries, pc.materials, pc.global, origin, dir, 1e-3, 1e4);

  Vec4 color;
  if (s.kind == RTHitKind.Hit) {
    // Sun + point lights + sky ambient. No sun shadow ray here (matches the raster-ish
    // debug look); the normal-mapped raster-convention normal drives the lighting.
    let direct = rt_direct_lighting(pc.tlas.get(), pc.global, s.pos_ws, s.normal_mapped, s.hit_t, /*sun_shadow*/ false);
    let lit = s.albedo * (pc.global.sky_color * 0.3 + direct);

    let mapped = lit / (lit + 1.0); // Reinhard so HDR stays viewable (no post-process here)
    color = Vec4(pow(mapped, Vec3(1.0 / 2.2)), 1.0);
  } else {
    color = Vec4(0.02, 0.02, 0.04, 1.0);
  }

  pc.out_image.store(px, color);
}
