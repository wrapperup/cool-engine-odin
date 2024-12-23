import bindless;
import common;
import consts;
import ibl;
import standard_brdf;
import types;

struct DrawPushConstants {
  Vertex *vertex_buffer;
  GlobalData *global_data_buffer;
};

struct VertexInput {
  uint vertex_index : SV_VertexID;
};

[vk_push_constant] DrawPushConstants pc;

[shader("vertex")]
FragmentInput vertex_main(VertexInput input) {
  let vertex = pc.vertex_buffer[input.vertex_index];

  let view_to_clip = pc.global_data_buffer.view_to_clip;
  var world_to_view = pc.global_data_buffer.world_to_view;

  world_to_view[0][3] = 0;
  world_to_view[1][3] = 0;
  world_to_view[2][3] = 0;

  let world_to_clip = mul(view_to_clip, world_to_view);

  let vert_pos_ws = float4(vertex.position, 1.0);

  FragmentInput output;
  output.pos = mul(world_to_clip, vert_pos_ws);
  output.frag_pos = vert_pos_ws.xyz;

  return output;
}

struct FragmentInput {
  float4 pos : SV_Position;
  float3 frag_pos;
};

struct FragmentOutput {
  [vk_location(0)]
  float4 frag_color : COLOR0;
};

[shader("fragment")]
FragmentOutput fragment_main(FragmentInput i) {
  let color = pc.global_data_buffer.sky_color * ENVIRONMENT_MAP_ID.sample_level(ENVIRONMENT_SAMPLER_ID, i.frag_pos, 0).xyz;

  FragmentOutput output;
  output.frag_color = float4(color, 1.0);

  return output;
}
