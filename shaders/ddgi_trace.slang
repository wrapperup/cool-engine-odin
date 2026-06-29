import bindless;
import common;
import types;
import world_space;
import ddgi_common;

[vk_push_constant]
DDGITracePush pc;

// Pass A: one workgroup per probe, one thread per ray. Trace the scene TLAS from the
// probe center, shade the hit (direct sun + sky ambient), write linear radiance + hit
// distance to radiance[probe * rays + ray]. (No bounce/shadow yet.)
[numthreads(192, 1, 1)]
[shader("compute")]
void compute_main(uint3 group_id: SV_GroupID, uint3 thread_id: SV_GroupThreadID) {
  let v = pc.volume;
  let probe = group_id.x;
  let ray = thread_id.x;

  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  if (probe >= ddgi_num_probes(counts) || ray >= v.rays_per_probe) {
    return;
  }

  let coord = ddgi_probe_coord(probe, counts);
  let origin = ddgi_probe_position(coord, v.grid_origin, v.probe_spacing) + ddgi_probe_offset(v, probe).xyz;
  let rot = float(v.frame_index) * 0.61803399 * DDGI_TWO_PI;
  let dir = ddgi_ray_direction(ray, v.rays_per_probe, rot);

  RayDesc r;
  r.Origin = origin;
  r.TMin = 0.0;
  r.Direction = dir;
  r.TMax = v.ray_max;

  RayQuery<RAY_FLAG_NONE> q;
  q.TraceRayInline(pc.tlas.get(), RAY_FLAG_NONE, 0xFF, r);
  q.Proceed();

  Vec3 radiance;
  float hit_t;
  if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT && !q.CommittedTriangleFrontFace()) {
    // Backface hit: this probe is inside/behind geometry in this direction. Capture no
    // light and mark the distance negative so the depth pass knows it's an occluder.
    radiance = Vec3(0.0);
    hit_t = -q.CommittedRayT();
  } else if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT) {
    hit_t = q.CommittedRayT();
    let hit_pos = origin + dir * hit_t;

    let geo = pc.geometries[q.CommittedInstanceID()];
    let prim = q.CommittedPrimitiveIndex();
    let i0 = geo.index_buffer[prim * 3 + 0];
    let i1 = geo.index_buffer[prim * 3 + 1];
    let i2 = geo.index_buffer[prim * 3 + 2];
    let v0 = geo.vertex_buffer[i0];
    let v1 = geo.vertex_buffer[i1];
    let v2 = geo.vertex_buffer[i2];

    let bc = q.CommittedTriangleBarycentrics();
    let bary = Vec3(1.0 - bc.x - bc.y, bc.x, bc.y);
    let n_interp = v0.normal * bary.x + v1.normal * bary.y + v2.normal * bary.z;
    let N = normalize(mul((float3x3)q.CommittedObjectToWorld3x4(), -n_interp));

    var uv = Vec2(v0.uv_x, v0.uv_y) * bary.x + Vec2(v1.uv_x, v1.uv_y) * bary.y + Vec2(v2.uv_x, v2.uv_y) * bary.z;
    if (geo.material_index == 0) {
      uv = get_world_space_uv(hit_pos, N) / 4.0;
    }
    let vcolor = v0.color * bary.x + v1.color * bary.y + v2.color * bary.z;

    let material = pc.materials[geo.material_index];
    let albedo = material.base_color_id.sample_level(pc.global.default_sampler, uv, 0).xyz * vcolor.xyz;

    let l = normalize(pc.global.sun_direction);
    let ndotl = clamp(dot(N, l), 0.0, 1.0);

    // Shadow ray toward the sun (first-hit terminate).
    float shadow = 1.0;
    if (ndotl > 0.0) {
      RayDesc sr;
      sr.Origin = hit_pos + N * 0.02;
      sr.TMin = 0.0;
      sr.Direction = l;
      sr.TMax = 1e4;
      RayQuery<RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> sq;
      sq.TraceRayInline(pc.tlas.get(), RAY_FLAG_NONE, 0xFF, sr);
      sq.Proceed();
      if (sq.CommittedStatus() == COMMITTED_TRIANGLE_HIT) {
        shadow = 0.0;
      }
    }

    // Indirect bounce: this volume's previous-frame irradiance at the hit. Sky enters
    // via sky-seeing probes (miss = sky) and bounces over frames -> infinite bounce.
    // Scaled by intensity to tame multi-bounce buildup in high-albedo spaces.
    let indirect = ddgi_sample(pc.volume, hit_pos, N) * v.feedback;

    radiance = albedo * (pc.global.sun_color * ndotl * shadow + indirect);
  } else {
    hit_t = 1e30; // miss sentinel, independent of ray length (depth clamps it anyway)
    // Hemisphere sky: only the upper hemisphere contributes sky; at/below the horizon
    // is dark (void below map). Sharper than a gradient so down-facing probes go black.
    radiance = pc.global.sky_color * saturate(dir.y);
  }

  // Firefly clamp: a single ray landing on a bright sunlit texel while neighbors are
  // shadowed spikes the cosine-integrated probe and pops frame-to-frame as the ray set
  // rotates. Clamping per-ray luminance kills that shimmer at low hysteresis. Slightly
  // biases bright bounces dark; fine for diffuse GI.
  if (v.max_radiance > 0.0) {
    let luma = dot(radiance, Vec3(0.2126, 0.7152, 0.0722));
    if (luma > v.max_radiance) {
      radiance *= v.max_radiance / luma;
    }
  }

  pc.radiance[probe * v.rays_per_probe + ray] = Vec4(radiance, hit_t);
}
