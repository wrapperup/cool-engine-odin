struct DrawIndirectCommand {
  uint32_t vertexCount;
  uint32_t instanceCount;
  uint32_t firstVertex;
  uint32_t firstInstance;
}

struct ComputeInput {
  uint group_index : SV_GroupIndex;
};

struct VertexBuffer {
  uint vertex_count;
  Vertex *vertices;
}

struct Vertex {
  float3 position;
  float uv_x;
  float3 normal;
  float uv_y;
  float4 color;
};

struct PushConstantData {
  DrawIndirectCommand *draw_commands;
  VertexBuffer *vertex_buffers;
  uint entity_count;
};

[vk_push_constant]
ConstantBuffer<PushConstantData> push_constants;

[numthreads(1, 1, 1)]
[shader("compute")]
void write_draw_cmd() {
  DrawIndirectCommand draw_cmd;

  draw_cmd.vertexCount = 36 * (32 * 32 * 32);
  draw_cmd.firstVertex = 0;
  draw_cmd.instanceCount = 1;
  draw_cmd.firstInstance = 0;

  push_constants.draw_commands[0] = draw_cmd;
}
