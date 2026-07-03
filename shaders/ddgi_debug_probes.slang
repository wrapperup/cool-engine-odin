import bindless;
import common;
import types;
import ddgi_common;

[vk_push_constant]
DDGIProbePush pc;

// Instanced debug spheres: one per probe, placed at its grid position, each fragment
// shaded by sampling that probe's octahedral irradiance in the surface normal
// direction. Renders into the HDR scene (linear out -> normal tonemap downstream).
struct V2F {
  Vec4 pos_cs : SV_Position;
  Vec3 normal_ws;
  nointerpolation uint probe : PROBE;
  nointerpolation float active : ACTIVE;
};

[shader("vertex")]
V2F vertex_main(uint vid: SV_VertexID, uint iid: SV_InstanceID) {
  let v = pc.volume[0];
  uint3 counts = uint3(v.grid_counts[0], v.grid_counts[1], v.grid_counts[2]);
  let coord = ddgi_probe_coord(iid, counts);
  let probe_off = ddgi_probe_offset(v, iid);
  let center = ddgi_probe_position(coord, v.grid_origin, v.probe_spacing) + probe_off.xyz;

  let vert = pc.vertex_buffer[vid];
  let world = center + vert.position * pc.probe_radius;

  let world_to_clip = mul(pc.global.view_to_clip, pc.global.world_to_view);

  V2F o;
  o.pos_cs = mul(world_to_clip, Vec4(world, 1.0));
  o.normal_ws = normalize(vert.normal);
  o.probe = iid;
  o.active = probe_off.w;
  return o;
}

[shader("fragment")]
Vec4 fragment_main(V2F i) : SV_Target {
  if (i.active < 0.5) {
    discard; // buried/inactive probe -> not drawn
  }
  let irr = ddgi_sample_irradiance(pc.volume[0], i.probe, normalize(i.normal_ws));
  return Vec4(irr, 1.0); // linear; tonemapped by post-processing
}
