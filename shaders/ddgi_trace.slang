import bindless;
import common;
import types;
import ddgi_common;
import rt_common;

[vk_push_constant]
DDGITracePush pc;

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

  let s = rt_trace_surface(pc.tlas.get(), pc.instances, pc.materials, pc.global, origin, dir, 0.0, v.ray_max);

  Vec3 radiance;
  float hit_t;
  if (s.kind == RTHitKind.Backface) {
    // backface hit, don't contribute.
    radiance = Vec3(0.0);
    hit_t = -s.hit_t;
  } else if (s.kind == RTHitKind.Hit) {
    hit_t = s.hit_t;

    let fb_bias = 0.2 * min(v.probe_spacing.x, min(v.probe_spacing.y, v.probe_spacing.z));
    let indirect = ddgi_sample_volumes(pc.global.ddgi_volumes, s.pos_ws, s.normal, fb_bias) * v.feedback;

    let direct = rt_direct_lighting(pc.tlas.get(), pc.global, s.pos_ws, s.normal, s.hit_t, /*sun_shadow*/ true);
    radiance = s.albedo * (direct + indirect);
  } else {
    hit_t = 1e30;
    // sky miss
    let env = pc.global.environment;
    radiance = pc.global.sky_color * env.env_map.sample_level(env.env_sampler, dir, 0).rgb;
  }

  // firefly clamp
  if (v.max_radiance > 0.0) {
    let luma = dot(radiance, Vec3(0.2126, 0.7152, 0.0722));
    if (luma > v.max_radiance) {
      radiance *= v.max_radiance / luma;
    }
  }

  pc.radiance[probe * v.rays_per_probe + ray] = Vec4(radiance, hit_t);
}
