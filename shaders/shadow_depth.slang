import common;
import types;

struct DrawPushConstants {
  Vertex *vertex_buffer;
  Mat4x4 *model_matrices;
  Mat4x4 *shadow_cascade_matrices;
  u32 model_index;
  u32 cascade_index;
};

struct VertexInput {
  u32 vertex_index : SV_VertexID;
};

[vk_push_constant]
DrawPushConstants pc;

struct V2PShadow {
  Vec4 pos : SV_Position;
}

[shader("vertex")]
V2PShadow vertex_main(VertexInput input) {
  let vertex = pc.vertex_buffer[input.vertex_index];

  let model_to_world = pc.model_matrices[pc.model_index];
  let view_projection_matrix = pc.shadow_cascade_matrices[pc.cascade_index];

  V2PShadow output;
  output.pos =
      view_projection_matrix * (model_to_world * Vec4(vertex.position, 1.0));

  return output;
}
