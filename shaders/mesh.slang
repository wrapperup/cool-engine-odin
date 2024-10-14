import bindless;
import standard_brdf;
import ibl;

static const float4x4 biasMat = {
  0.5, 0.0, 0.0, 0.5, //
  0.0, 0.5, 0.0, 0.5, //
  0.0, 0.0, 1.0, 0.0, //
  0.0, 0.0, 0.0, 1.0, //
};

struct Vertex {
  float3 position;
  float uv_x;
  float3 normal;
  float uv_y;
  float4 color;
};

struct SkelVertexAttribute {
  uint8_t joints[4];
  float weights[4];
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

struct DrawPushConstants {
  GlobalData *global_data_buffer;
  Vertex *vertex_buffer;
  float4x4 *model_matrices;
  float4x4 *joint_matrices;
  SkelVertexAttribute *attrs;
};

struct VertexInput {
  uint vertex_index : SV_VertexID;
  uint instance_id : SV_InstanceID;
};

struct PbrMaterialParams {
  float4 base_color;
  float4 emissive;
  float metallic;
  float roughness;
  float reflectance;
  float ambient_occlussion;
}

[vk_push_constant]
DrawPushConstants pc;

[shader("vertex")]
FragmentInput vertex_main(VertexInput input) {
  let vertex = pc.vertex_buffer[input.vertex_index];
  let attrs = pc.attrs[input.vertex_index];

  let view_projection_matrix = pc.global_data_buffer.view_projection_matrix;
  let sun_view_projection_matrix =
      pc.global_data_buffer.sun_view_projection_matrix;

  var skin_mat = attrs.weights[0] * pc.joint_matrices[attrs.joints[0]] +
                 attrs.weights[1] * pc.joint_matrices[attrs.joints[1]] +
                 attrs.weights[2] * pc.joint_matrices[attrs.joints[2]] +
                 attrs.weights[3] * pc.joint_matrices[attrs.joints[3]];

  let vert_pos = mul(skin_mat, float4(vertex.position, 1.0));
  let vert_norm = mul(skin_mat, float4(vertex.normal, 0.0));
  let vert_uv = float2(vertex.uv_x, vertex.uv_y);

  FragmentInput output;
  output.color = 1;
  output.pos = mul(view_projection_matrix,
                   mul(pc.model_matrices[input.instance_id], vert_pos));
  output.normal = mul(pc.model_matrices[input.instance_id], vert_norm).xyz;
  output.uv = vert_uv;
  output.frag_pos = vert_pos.xyz;
  output.sun_space_pos =
      mul(biasMat, mul(sun_view_projection_matrix,
                       mul(pc.model_matrices[input.instance_id], vert_pos)));

  return output;
}

struct FragmentInput {
  float4 pos : SV_Position;
  float3 color : COLOR0;
  float2 uv : TEXCOORD0;
  float3 normal;
  float3 frag_pos;
  float4 sun_space_pos;
  uint tex_id;
};

struct FragmentOutput {
  [vk_location(0)]
  float4 frag_color : COLOR0;
};

[shader("fragment")]
FragmentOutput fragment_main(FragmentInput i) {
  float3 frag_pos = i.frag_pos;
  float3 view_pos = pc.global_data_buffer.camera_pos;

  float3 n = normalize(i.normal);
  float3 v = normalize(view_pos - frag_pos);
  float3 l = normalize(pc.global_data_buffer.sun_pos); // Directional light
  float3 h = normalize(v + l);

  float NoL = clamp(dot(n, l), 0.0, 1.0);

  float3 base_color = 1; // For now
  float metallic = 1.f;
  float reflectance = 0.5f;
  float roughness = 0.25;
  float linear_roughness = roughness * roughness;

  float3 f0 = 0.16f * reflectance * reflectance * (1.0f - metallic) + base_color * metallic;
  float3 diffuse = (1.0 - metallic) * base_color.rgb;

  float3 frag_color = (NoL * pc.global_data_buffer.sun_color) * standard_brdf(diffuse, linear_roughness, v, l, n, h, f0, NoL);
  frag_color += pc.global_data_buffer.sky_color * base_color;

  frag_color = evaluate_ibl(n, v, diffuse, f0, 1.0, roughness);
  // frag_color = sample_cubemap(TEST_ENVIRONMENT_MAP_ID, n, 0).rgb;

  // printf("%f %f %f\n", v);

  FragmentOutput output;
  output.frag_color = float4(frag_color, 1.0f);

  return output;
}
