import bindless;
import common;
import consts;
import ibl;
import standard_brdf;

struct DrawPushConstants {
  float4x4 view_projection_matrix;
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

  let view_projection_matrix = pc.view_projection_matrix;

  let vert_pos = float4(vertex.position, 1.0);

  FragmentInput output;
  output.pos = mul(view_projection_matrix, vert_pos);
  output.frag_pos = vert_pos.xyz;

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
