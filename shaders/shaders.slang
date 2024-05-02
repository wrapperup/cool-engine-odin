struct VertexInput {
  uint vertex_index : SV_VertexID;
};

struct V2P {
  float4 pos : SV_Position;
  [vk_location(0)]
  float3 color : COLOR0;
  [vk_location(1)]
  float2 uv : TEXCOORD0;
};

struct PSOutput {
  [vk_location(0)]
  float4 frag_color : COLOR0;
};

struct Vertex {
  float3 position;
  float uv_x;
  float3 normal;
  float uv_y;
  float4 color;
};

struct GPUDrawPushConstants {
  float4x4 view_matrix;
  float4x4 view_it_matrix;
  float4x4 projection_matrix;
  uint8_t *voxel_buffer;
};

[vk_push_constant]
ConstantBuffer<GPUDrawPushConstants> push_constants;

static const uint3 dir_face_lut_x[2][6] = {
  {
    { 0, 1, 1 }, // x-
    { 0, 0, 0 },
    { 0, 1, 0 },
    { 0, 0, 0 },
    { 0, 1, 1 },
    { 0, 0, 1 },
  },
  {
    { 1, 1, 1 }, // x+
    { 1, 1, 0 },
    { 1, 0, 0 },
    { 1, 0, 0 },
    { 1, 0, 1 },
    { 1, 1, 1 },
  },
};

static const uint3 dir_face_lut_y[2][6] = {
  {
    { 1, 1, 1 }, // y-
    { 0, 1, 1 },
    { 0, 1, 0 },
    { 0, 1, 0 },
    { 1, 1, 0 },
    { 1, 1, 1 },
  },
  {
    { 0, 0, 1 }, // y+
    { 1, 0, 1 },
    { 0, 0, 0 },
    { 1, 0, 0 },
    { 0, 0, 0 },
    { 1, 0, 1 },
  },
};

static const uint3 dir_face_lut_z[2][6] = {
  {
    { 0, 0, 0 }, // z-
    { 1, 0, 0 },
    { 1, 1, 0 },
    { 1, 1, 0 },
    { 0, 1, 0 },
    { 0, 0, 0 },
  },
  {
    { 0, 1, 1 }, // z+
    { 1, 1, 1 },
    { 0, 0, 1 },
    { 1, 0, 1 },
    { 0, 0, 1 },
    { 1, 1, 1 },
  },
};

static const int3 normals[6] = {
  { 0, 0, 1 },  // z+
  { 0, 0, -1 }, // z-
  { 1, 0, 0 },  // x+
  { -1, 0, 0 }, // x-
  { 0, 1, 0 },  // y+
  { 0, -1, 0 }, // y-
};

uint3 index_to_pos(uint idx) {
  uint x = (idx % 32);
  uint y = (idx / 32) % 32;
  uint z = (idx / 32) / 32;

  return uint3(x, y, z);
}

static const float3 fake_light = { 0.0976, 0.9759, 0.1952 };

float3 get_position_from_lut_index(uint idx, bool x_pos, bool y_pos, bool z_pos) {
  let table = (idx / 3) % 3;
  let vert_idx = idx % 6;

  switch (table) {
  case 0:
    return dir_face_lut_x[x_pos > 0 ? 1 : 0][vert_idx];
  case 1:
    return dir_face_lut_y[y_pos > 0 ? 1 : 0][vert_idx];
  case 2:
    return dir_face_lut_z[z_pos > 0 ? 1 : 0][vert_idx];
  }

  return float3(0);
}

float3 get_normal_from_lut_index(uint idx, bool x_pos, bool y_pos, bool z_pos) {
  let table = (idx / 3) % 3;

  switch (table) {
  case 0:
    return float3(x_pos > 0 ? -1 : 1, 0, 0);
  case 1:
    return float3(0, x_pos > 0 ? -1 : 1, 0);
  case 2:
    return float3(0, 0, x_pos > 0 ? -1 : 1);
  }

  return float3(0);
}

[shader("vertex")]
V2P vertex_main(VertexInput input) {
  let voxel = push_constants.voxel_buffer[input.vertex_index / 18];

  let view_matrix = push_constants.view_matrix;
  let projection_matrix = push_constants.projection_matrix;

  Vertex v;
  if (voxel > 3) {
    v.position = get_position_from_lut_index(input.vertex_index, false, false, false);
    v.position *= voxel / 9.f;
    // v.position.y = -v.position.y;
    v.position += index_to_pos(input.vertex_index / 18);
    v.position -= 16;

    v.normal = get_normal_from_lut_index(input.vertex_index, false, false, false);

    V2P output;
    output.pos =
        mul(projection_matrix, mul(view_matrix, float4(v.position, 1.0)));
    // output.pos = mul(view_matrix, mul(world_matrix,
    // float4(v.position, 1.0))); output.color = v.color.xyz; output.color =
    // v.position.xyz / 8;
    output.color = lerp(((dot(v.normal, fake_light) / 0.5) + 0.5), 1.f,
                        1.2f - (voxel / 8.f));
    // output.color = 1.0;
    output.color.r *= max(log(voxel / 8.f) + 0.25, 0.0);
    output.color.g *= max(log(voxel / 8.f) + 0.5, 0.3);
    output.color.b *= max(log(voxel / 8.f) + 0.5, 0.4);

    return output;
  } else {
    V2P x;
    return x;
  }
}

[shader("fragment")]
PSOutput fragment_main(V2P input) {
  PSOutput output;
  output.frag_color = float4(input.color, 1.f);

  return output;
}
