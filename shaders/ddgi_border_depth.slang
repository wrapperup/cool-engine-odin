import bindless;
import common;
import types;
import ddgi_common;

[vk_push_constant]
DDGIUpdatePush pc; // {volume, radiance(unused), irradiance := DEPTH atlas}

// Octahedral border copy for the depth atlas (interior 14, tile 16).
[numthreads(16, 16, 1)] // = DDGI_DEPTH_TILE
[shader("compute")]
void compute_main(uint3 group_id: SV_GroupID, uint3 thread_id: SV_GroupThreadID) {
  let v = pc.volume;
  let probe = group_id.x;
  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  if (probe >= ddgi_num_probes(counts)) {
    return;
  }

  const int L = 14; // DDGI_PROBE_DEPTH_TEXELS (interior). Full coords [0, L+1].
  int2 c = int2(thread_id.xy);
  bool x_edge = c.x == 0 || c.x == L + 1;
  bool y_edge = c.y == 0 || c.y == L + 1;
  if (!x_edge && !y_edge) {
    return;
  }

  int2 src;
  if (x_edge && y_edge) {
    src = int2(c.x == 0 ? L : 1, c.y == 0 ? L : 1);
  } else if (x_edge) {
    src = int2(c.x == 0 ? 1 : L, L + 1 - c.y);
  } else {
    src = int2(L + 1 - c.x, c.y == 0 ? 1 : L);
  }

  let coord = ddgi_probe_coord(probe, counts);
  let base = int2(ddgi_probe_tile(coord, counts)) * 16; // DDGI_DEPTH_TILE
  pc.irradiance.store(uint2(base + c), pc.irradiance.load(uint2(base + src)));
}
