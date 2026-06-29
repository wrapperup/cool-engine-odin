import bindless;
import common;
import types;
import ddgi_common;

[vk_push_constant]
DDGIUpdatePush pc;

// Pass B (irradiance): one workgroup per probe, one thread per interior texel. Each
// texel's octahedral direction integrates all rays weighted by max(0, dot(texel_dir,
// ray_dir)), then exponentially blends into the atlas via hysteresis.
[numthreads(6, 6, 1)] // = DDGI_PROBE_IRR_TEXELS
[shader("compute")]
void compute_main(uint3 group_id: SV_GroupID, uint3 thread_id: SV_GroupThreadID) {
  let v = pc.volume;
  let probe = group_id.x;

  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  if (probe >= ddgi_num_probes(counts)) {
    return;
  }

  const uint INTERIOR = 6; // DDGI_PROBE_IRR_TEXELS
  const uint TILE = 8;     // DDGI_IRR_TILE

  let coord = ddgi_probe_coord(probe, counts);
  let tile = ddgi_probe_tile(coord, counts);
  let local = thread_id.xy; // [0, INTERIOR)

  // octahedral direction this texel represents
  let oct = (Vec2(local) + 0.5) / float(INTERIOR) * 2.0 - 1.0;
  let texel_dir = ddgi_oct_decode(oct);

  let rot = float(v.frame_index) * 0.61803399 * DDGI_TWO_PI;
  Vec3 sum = Vec3(0.0);
  float wsum = 0.0;
  for (uint i = 0; i < v.rays_per_probe; i++) {
    let ray_dir = ddgi_ray_direction(i, v.rays_per_probe, rot);
    let w = max(0.0, dot(texel_dir, ray_dir));
    if (w > 0.0) {
      sum += pc.radiance[probe * v.rays_per_probe + i].rgb * w;
      wsum += w;
    }
  }
  let result = wsum > 0.0 ? sum / wsum : Vec3(0.0);

  // interior texel -> atlas pixel (+1px border)
  let px = tile * TILE + uint2(1, 1) + local;
  let prev = pc.irradiance.load(px).rgb;
  let blended = lerp(result, prev, v.hysteresis);
  pc.irradiance.store(px, Vec4(blended, 1.0));
}
