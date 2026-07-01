import bindless;
import common;
import types;

static const float DDGI_TWO_PI = 6.28318530718;

Vec2 ddgi_oct_encode(Vec3 dir) {
  Vec3 n = dir / (abs(dir.x) + abs(dir.y) + abs(dir.z));
  Vec2 e = n.z >= 0.0
      ? n.xy
      : (Vec2(1.0) - abs(Vec2(n.y, n.x))) * Vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
  return e;
}

Vec3 ddgi_oct_decode(Vec2 e) {
  Vec3 n = Vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
  float t = saturate(-n.z);
  n.x += n.x >= 0.0 ? -t : t;
  n.y += n.y >= 0.0 ? -t : t;
  return normalize(n);
}

Vec3 ddgi_ray_direction(uint i, uint n, float rot) {
  const float GOLDEN = 2.39996323; // golden angle (radians)
  float z = 1.0 - (2.0 * float(i) + 1.0) / float(n);
  float r = sqrt(max(0.0, 1.0 - z * z));
  float phi = float(i) * GOLDEN + rot;
  return Vec3(r * cos(phi), r * sin(phi), z);
}

uint3 ddgi_probe_coord(uint p, uint3 counts) {
  return uint3(p % counts.x, (p / counts.x) % counts.y, p / (counts.x * counts.y));
}

uint ddgi_probe_index(uint3 c, uint3 counts) {
  return c.x + c.y * counts.x + c.z * counts.x * counts.y;
}

uint2 ddgi_probe_tile(uint3 c, uint3 counts) {
  return uint2(c.x + c.z * counts.x, c.y);
}

Vec3 ddgi_probe_position(uint3 c, Vec3 origin, Vec3 spacing) {
  return origin + Vec3(c) * spacing;
}

uint ddgi_num_probes(uint3 counts) {
  return counts.x * counts.y * counts.z;
}

Vec4 ddgi_probe_offset(DDGIVolume* v, uint probe) {
  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  let tile = ddgi_probe_tile(ddgi_probe_coord(probe, counts), counts);
  uint2 sz;
  v.offset.get_dimensions(sz.x, sz.y);
  let uv = (Vec2(tile) + 0.5) / Vec2(sz);
  return v.offset.sample_level(v.sampler, uv, 0);
}

Vec3 ddgi_sample_irradiance(DDGIVolume* v, uint probe, Vec3 dir) {
  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  let coord = ddgi_probe_coord(probe, counts);
  let tile = ddgi_probe_tile(coord, counts);

  const float INTERIOR = 6.0; // DDGI_PROBE_IRR_TEXELS
  const float TILE = 8.0;     // DDGI_IRR_TILE

  let oct = ddgi_oct_encode(dir) * 0.5 + 0.5; // [0,1]
  let px = Vec2(tile) * TILE + 1.0 + oct * INTERIOR; // +1px border

  uint2 atlas_size;
  v.irradiance.get_dimensions(atlas_size.x, atlas_size.y);
  let uv = px / Vec2(atlas_size);
  return v.irradiance.sample_level(v.sampler, uv, 0).rgb;
}

Vec2 ddgi_sample_depth(DDGIVolume* v, uint probe, Vec3 dir) {
  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  let coord = ddgi_probe_coord(probe, counts);
  let tile = ddgi_probe_tile(coord, counts);

  const float INTERIOR = 14.0; // DDGI_PROBE_DEPTH_TEXELS
  const float TILE = 16.0;     // DDGI_DEPTH_TILE

  let oct = ddgi_oct_encode(dir) * 0.5 + 0.5;
  let px = Vec2(tile) * TILE + 1.0 + oct * INTERIOR;

  uint2 atlas_size;
  v.depth.get_dimensions(atlas_size.x, atlas_size.y);
  let uv = px / Vec2(atlas_size);
  return v.depth.sample_level(v.sampler, uv, 0).rg;
}

Vec3 ddgi_sample(DDGIVolume* v, Vec3 world_pos, Vec3 normal) {
  return ddgi_sample(v, world_pos, normal, v.normal_bias);
}

// Explicit-bias overload. The feedback path (ddgi_trace) passes its own small bias so the
// display path can use normal_bias = 0 (max contact detail) without the bounce loop
// self-reinforcing into a white runaway in high-albedo rooms.
Vec3 ddgi_sample(DDGIVolume* v, Vec3 world_pos, Vec3 normal, float bias) {
  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  let biased = world_pos + normal * bias;
  let g = (biased - v.grid_origin) / v.probe_spacing;
  int3 base = int3(floor(g));
  let f = frac(g);

  Vec3 irr = Vec3(0.0);
  float weight_sum = 0.0; // visibility-weighted
  for (uint c = 0; c < 8; c++) {
    int3 off = int3(c & 1, (c >> 1) & 1, (c >> 2) & 1);
    int3 pc = clamp(base + off, int3(0), int3(counts) - 1);
    let tri3 = lerp(1.0 - f, f, Vec3(off));
    let tri = tri3.x * tri3.y * tri3.z;
    if (tri <= 0.0) {
      continue;
    }

    let probe = ddgi_probe_index(uint3(pc), counts);
    let probe_off = ddgi_probe_offset(v, probe);
    if (probe_off.w < 0.5) {
      continue; // inactive (buried) probe -> excluded entirely, not even counted
    }
    let probe_pos = ddgi_probe_position(uint3(pc), v.grid_origin, v.probe_spacing) + probe_off.xyz;

    // chebyshev visibility
    let to_sample = biased - probe_pos;
    let dist = length(to_sample);
    let moments = ddgi_sample_depth(v, probe, normalize(to_sample));
    let mean = moments.x;
    float vis = 1.0;
    if (dist > mean) {
      let variance = max(moments.y - mean * mean, 1e-5);
      let cheb = variance / (variance + (dist - mean) * (dist - mean));
      vis = pow(max(cheb, 0.0), v.cheb_sharpness);
    }

    let to_probe = -normalize(to_sample);
    let backface = (dot(to_probe, normal) + 1.0) * 0.5;
    let w_back = backface * backface;

    let weight = tri * vis * w_back;
    weight_sum += weight;
    irr += ddgi_sample_irradiance(v, probe, normal) * weight;
  }
  // Normalize by the visibility-weighted sum: an edge point reaches the weighted average of
  // the probes it can see (slightly darker, not black). Leak control comes from occluded
  // probes weighing less, not from crushing the result to zero.
  return irr / max(weight_sum, 1e-5);
}
