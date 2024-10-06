struct DrawPushConstants {
  GlobalData *global_data_buffer;
  Vertex *vertex_buffer;
  float4x4 *model_matrices;
};

struct GlobalData {
  float4x4 view_projection_matrix;
  float4x4 view_projection_i_matrix;
  float4x4 sun_view_projection_matrix;
  float4x4 sun_view_projection_i_matrix;
  float3 sun_color;
  float bias;
  float3 sky_color;
  float pad_0;
  float3 camera_pos;
  float pad_1;
  float3 sun_pos;
  float pad_2;
};

struct Vertex {
  float3 position;
  float uv_x;
  float3 normal;
  float uv_y;
  float4 color;
};

struct SkelVertex {
  float3 position;
  float uv_x;
  float3 normal;
  float uv_y;
  float4 color;
  uint8_t joints[4];
  uint4 weights;
};
