struct Vertex {
  float3 position;
  float uv_x;
  float3 normal;
  float uv_y;
  float4 color;
  float4 tangent;
};

struct Environment {
  float4 sh_coeffs[9];
}

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
	Environment environment;
};

struct PBRMaterial {
  uint base_color_id;
  uint normal_map_id;
  uint ao_roughness_metallic;
}

float3 srgb_to_linear(float3 color) {
  return pow(color, 2.2);
}

float3 linear_to_srgb(float3 color) {
  return pow(color, 1.0 / 2.2);
}

