import bindless;
import common;
import types;
import ddgi_common;
import rt_common;

[vk_push_constant]
DDGITracePush pc;

// Pass A: one workgroup per probe, one thread per ray. Trace the scene TLAS from the
// probe center, shade the hit (direct sun + point lights + indirect bounce), write
// linear radiance + hit distance to radiance[probe * rays + ray].
[numthreads(384, 1, 1)]
[shader("compute")]
void compute_main(uint3 group_id: SV_GroupID, uint3 thread_id: SV_GroupThreadID) {
  let v = pc.volume[0];
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

  let s = rt_trace_surface(pc.tlas.get(), pc.geometries, pc.materials, pc.global, origin, dir, 0.0, v.ray_max);

  Vec3 radiance;
  float hit_t;
  if (s.kind == RTHitKind.Backface) {
    // Backface hit: this probe is inside/behind geometry in this direction. Capture no
    // light and mark the distance negative so the depth pass knows it's an occluder.
    radiance = Vec3(0.0);
    hit_t = -s.hit_t;
  } else if (s.kind == RTHitKind.Hit) {
    hit_t = s.hit_t;

    // Indirect bounce: previous-frame irradiance at the hit, selected from the FULL volume
    // array (world-space select) — a hit inside another volume samples that volume's probes,
    // which is how light propagates between volumes. Sky enters via sky-seeing probes
    // (miss = sky) and bounces over frames -> infinite bounce.
    // Feedback path uses its own small bias (independent of the display normal_bias) so the
    // bounce loop stays stable even when display bias is 0. ~0.2 cells off the surface.
    let fb_bias = 0.2 * min(v.probe_spacing.x, min(v.probe_spacing.y, v.probe_spacing.z));
    let indirect = ddgi_sample_volumes(pc.global.ddgi_volumes, s.pos_ws, s.normal, fb_bias) * v.feedback;

    let direct = rt_direct_lighting(pc.tlas.get(), pc.global, s.pos_ws, s.normal, s.hit_t, /*sun_shadow*/ true);
    radiance = s.albedo * (direct + indirect);
  } else {
    hit_t = 1e30; // miss sentinel, independent of ray length (depth clamps it anyway)
    // Sky miss: sample the environment cubemap in the ray direction (matches skybox.slang),
    // so probes integrate the real environment lighting instead of a hemisphere fake.
    let env = pc.global.environment;
    radiance = pc.global.sky_color * env.env_map.sample_level(env.env_sampler, dir, 0).rgb;
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
