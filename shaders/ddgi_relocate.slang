import bindless;
import common;
import types;
import ddgi_common;

[vk_push_constant]
DDGIUpdatePush pc; // {volume, radiance, irradiance := OFFSET atlas (1 texel/probe)}

// Probe relocation: scan a probe's rays (distance in .w, negative = backface) and nudge
// the probe out of geometry / away from surfaces, accumulating into the offset atlas.
// One thread per probe.
[numthreads(64, 1, 1)]
[shader("compute")]
void compute_main(uint3 dispatch_id: SV_DispatchThreadID) {
  let v = pc.volume;
  let probe = dispatch_id.x;
  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  if (probe >= ddgi_num_probes(counts)) {
    return;
  }

  let rot = float(v.frame_index) * 0.61803399 * DDGI_TWO_PI;

  float closest_back = 1e27;
  float closest_front = 1e27;
  float farthest_front = 0.0;
  Vec3 closest_back_dir = Vec3(0, 0, 1);
  Vec3 closest_front_dir = Vec3(0, 0, 1);
  uint back_count = 0;

  for (uint i = 0; i < v.rays_per_probe; i++) {
    let dir = ddgi_ray_direction(i, v.rays_per_probe, rot);
    let d = pc.radiance[probe * v.rays_per_probe + i].w;
    if (d < 0.0) {
      back_count++;
      let ad = -d;
      if (ad < closest_back) {
        closest_back = ad;
        closest_back_dir = dir;
      }
    } else {
      if (d < closest_front) {
        closest_front = d;
        closest_front_dir = dir;
      }
      farthest_front = max(farthest_front, d);
    }
  }

  let tile = ddgi_probe_tile(ddgi_probe_coord(probe, counts), counts);
  let cur = pc.irradiance.load(tile);
  Vec3 current = cur.xyz;

  // Classify probes and exclude the useless ones:
  //  - buried in geometry (mostly backface hits)
  //  - floating in the void outside the map (no ray hit any real frontface; all are
  //    misses, which store the sentinel distance max_distance*4)
  // Hysteresis (inactive >0.6, active <0.3, hold between) prevents boundary flicker.
  let backface_frac = float(back_count) / float(v.rays_per_probe);
  let has_frontface = closest_front < 1e29; // a real hit (misses store the 1e30 sentinel)
  float target_active = cur.w >= 0.5 ? 1.0 : 0.0; // default: keep current state
  if (backface_frac > 0.6 || !has_frontface) {
    target_active = 0.0;
  } else if (backface_frac < 0.3 && has_frontface) {
    target_active = 1.0;
  }
  let new_active = lerp(target_active, cur.w, 0.9);

  let spacing_min = min(v.probe_spacing.x, min(v.probe_spacing.y, v.probe_spacing.z));
  let min_dist = 0.3 * spacing_min;
  let max_offset = v.relocation_max * spacing_min;

  Vec3 new_offset = current;
  if (float(back_count) / float(v.rays_per_probe) > 0.25) {
    // Mostly inside geometry: step past the nearest inner surface into open space.
    new_offset = current + closest_back_dir * (closest_back + min_dist);
  } else if (closest_front < min_dist) {
    // Too close to a surface: back away from it.
    new_offset = current - closest_front_dir * (min_dist - closest_front);
  }
  // else: well placed, keep the current offset.

  // The ray set rotates each frame, so the raw target is noisy and its direction can
  // flip frame-to-frame -> shaky. Heavily low-pass toward the target AND hard-cap the
  // per-frame movement, so a direction flip can only produce a tiny wiggle while the
  // consistent bias still glides the probe out over ~1s.
  new_offset = lerp(new_offset, current, 0.99);
  let step = new_offset - current;
  let max_step = 0.02 * spacing_min;
  if (length(step) > max_step) {
    new_offset = current + normalize(step) * max_step;
  }

  if (length(new_offset) > max_offset) {
    new_offset = normalize(new_offset) * max_offset;
  }

  pc.irradiance.store(tile, Vec4(new_offset, new_active));
}
