import bindless;
import common;
import types;
import ddgi_common;

[vk_push_constant]
DDGIUpdatePush pc; // {volume, radiance, irradiance := DEPTH atlas here}

// Depth update for Chebyshev visibility: per octahedral texel, integrate hit distance
// (sharper cosine power than irradiance) as (mean, mean^2). Stored in the RG16F depth
// atlas. `pc.irradiance` is bound to the depth atlas by the CPU.
[numthreads(14, 14, 1)] // = DDGI_PROBE_DEPTH_TEXELS
[shader("compute")]
void compute_main(uint3 group_id: SV_GroupID, uint3 thread_id: SV_GroupThreadID) {
  let v = pc.volume;
  let probe = group_id.x;
  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  if (probe >= ddgi_num_probes(counts)) {
    return;
  }

  const uint INTERIOR = 14; // DDGI_PROBE_DEPTH_TEXELS
  const uint TILE = 16;     // DDGI_DEPTH_TILE
  const float SHARPNESS = 50.0;

  let coord = ddgi_probe_coord(probe, counts);
  let tile = ddgi_probe_tile(coord, counts);
  let local = thread_id.xy;

  let oct = (Vec2(local) + 0.5) / float(INTERIOR) * 2.0 - 1.0;
  let texel_dir = ddgi_oct_decode(oct);

  let rot = float(v.frame_index) * 0.61803399 * DDGI_TWO_PI;
  Vec2 sum = Vec2(0.0);
  float wsum = 0.0;
  for (uint i = 0; i < v.rays_per_probe; i++) {
    let ray_dir = ddgi_ray_direction(i, v.rays_per_probe, rot);
    let w = pow(max(0.0, dot(texel_dir, ray_dir)), SHARPNESS);
    if (w > 1e-6) {
      let raw = pc.radiance[probe * v.rays_per_probe + i].w;
      // Backface (negative): record a shortened distance so the probe reads geometry
      // very close in that direction -> occludes leaks (and buries in-wall probes).
      // Front face: bias the distance LONGER so surfaces right at a wall aren't
      // self-occluded (wall thickness keeps the far side beyond it -> no new leak).
      let d = raw < 0.0 ? min(-raw, v.max_distance) * 0.2 : min(raw + v.depth_bias, v.max_distance);
      sum += Vec2(d, d * d) * w;
      wsum += w;
    }
  }
  let result = wsum > 0.0 ? sum / wsum : Vec2(v.max_distance, v.max_distance * v.max_distance);

  let px = tile * TILE + uint2(1, 1) + local;
  let prev = pc.irradiance.load(px).rg;
  let blended = lerp(result, prev, v.hysteresis);
  pc.irradiance.store(px, Vec4(blended, 0.0, 0.0));
}
