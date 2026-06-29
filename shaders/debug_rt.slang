import bindless;
import common;
import types;
import world_space;

[vk_push_constant]
DebugRTPushConstants pc;

// One ray per pixel against the scene TLAS. On a hit, the geometry table resolves the
// instance back to its vertex/index buffers + material; albedo (texture * vertex color)
// is lit with a simple sun NoL + sky ambient using the interpolated world normal.
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

  RayDesc ray;
  ray.Origin = origin;
  ray.TMin = 1e-3;
  ray.Direction = dir;
  ray.TMax = 1e4;

  RayQuery<RAY_FLAG_NONE> q;
  q.TraceRayInline(pc.tlas.get(), RAY_FLAG_NONE, 0xFF, ray);
  q.Proceed();

  Vec4 color;
  if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT) {
    let geo = pc.geometries[q.CommittedInstanceID()];
    let prim = q.CommittedPrimitiveIndex();
    let i0 = geo.index_buffer[prim * 3 + 0];
    let i1 = geo.index_buffer[prim * 3 + 1];
    let i2 = geo.index_buffer[prim * 3 + 2];

    let bc = q.CommittedTriangleBarycentrics();
    let bary = Vec3(1.0 - bc.x - bc.y, bc.x, bc.y);

    let v0 = geo.vertex_buffer[i0];
    let v1 = geo.vertex_buffer[i1];
    let v2 = geo.vertex_buffer[i2];

    let uv = Vec2(v0.uv_x, v0.uv_y) * bary.x +
             Vec2(v1.uv_x, v1.uv_y) * bary.y +
             Vec2(v2.uv_x, v2.uv_y) * bary.z;

    let vcolor = v0.color * bary.x + v1.color * bary.y + v2.color * bary.z;

    let o2w = (Mat3x3)q.CommittedObjectToWorld3x4();
    // mesh.slang negates vertex.normal; the normal maps + world-space tangent are
    // authored against that orientation, so match it.
    let n_interp = v0.normal * bary.x + v1.normal * bary.y + v2.normal * bary.z;
    let N = normalize(mul(o2w, -n_interp));

    // material 0 uses world-space UV/tangent (matches mesh.slang).
    let pos_ws = origin + dir * q.CommittedRayT();
    var st_uv = uv;
    var tangent = v0.tangent * bary.x + v1.tangent * bary.y + v2.tangent * bary.z;
    if (geo.material_index == 0) {
      tangent = get_world_space_tangent(N);
      st_uv = get_world_space_uv(pos_ws, N) / 4.0;
    }

    let T = normalize(mul(o2w, tangent.xyz));
    let B = cross(N, T) * tangent.w;
    let tbn = Mat3x3(T, B, N);

    let material = pc.materials[geo.material_index];
    // Compute shader: no derivatives, so explicit LOD 0 (sample_level, not sample).
    var tex_normal = material.normal_map_id.sample_level(pc.global.default_sampler, st_uv, 0).rgb * 2.0 - 1.0;
    tex_normal.y *= -1;
    let n_world = normalize(mul(tex_normal, tbn));

    // base_color = texture * vertex color (matches mesh.slang).
    let albedo = material.base_color_id.sample_level(pc.global.default_sampler, st_uv, 0).xyz * vcolor.xyz;

    // Simple directional light + sky ambient (l = direction to sun, per mesh.slang).
    let l = normalize(pc.global.sun_direction);
    let ndotl = clamp(dot(n_world, l), 0.0, 1.0);
    let lit = albedo * (pc.global.sky_color * 0.3 + pc.global.sun_color * ndotl);

    let mapped = lit / (lit + 1.0); // Reinhard so HDR stays viewable (no post-process here)
    color = Vec4(pow(mapped, Vec3(1.0 / 2.2)), 1.0);
  } else {
    color = Vec4(0.02, 0.02, 0.04, 1.0);
  }

  pc.out_image.store(px, color);
}
