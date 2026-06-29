import bindless;
import common;
import types;
import ddgi_common;

[vk_push_constant]
DDGIUpdatePush pc; // reuses {volume, radiance(unused), irradiance}

// Octahedral border copy: fills the 1px border of each probe tile with the wrapped
// edge values so bilinear sampling is seamless across the octahedron's fold. One
// workgroup per probe, one thread per full-tile texel; interior threads do nothing.
[numthreads(8, 8, 1)] // = DDGI_IRR_TILE
[shader("compute")]
void compute_main(uint3 group_id: SV_GroupID, uint3 thread_id: SV_GroupThreadID) {
  let v = pc.volume;
  let probe = group_id.x;
  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  if (probe >= ddgi_num_probes(counts)) {
    return;
  }

  const int L = 6; // DDGI_PROBE_IRR_TEXELS (interior). Full coords [0, L+1].
  int2 c = int2(thread_id.xy);
  bool x_edge = c.x == 0 || c.x == L + 1;
  bool y_edge = c.y == 0 || c.y == L + 1;
  if (!x_edge && !y_edge) {
    return; // interior, already written by the update pass
  }

  int2 src;
  if (x_edge && y_edge) {
    // corner -> diagonally opposite interior corner
    src = int2(c.x == 0 ? L : 1, c.y == 0 ? L : 1);
  } else if (x_edge) {
    // left/right -> adjacent interior column, y mirrored
    src = int2(c.x == 0 ? 1 : L, L + 1 - c.y);
  } else {
    // top/bottom -> adjacent interior row, x mirrored
    src = int2(L + 1 - c.x, c.y == 0 ? 1 : L);
  }

  let coord = ddgi_probe_coord(probe, counts);
  let base = int2(ddgi_probe_tile(coord, counts)) * 8; // DDGI_IRR_TILE
  pc.irradiance.store(uint2(base + c), pc.irradiance.load(uint2(base + src)));
}
