import bindless;
import common;
import shadows;
import standard_brdf;
import ibl;
import brdf;

static const float4x4 biasMat = {
  0.5, 0.0, 0.0, 0.5, //
  0.0, 0.5, 0.0, 0.5, //
  0.0, 0.0, 1.0, 0.0, //
  0.0, 0.0, 0.0, 1.0, //
};

struct DrawPushConstants {
  GlobalData *global_data_buffer;
  Vertex *vertex_buffer;
  float4x4 *model_matrices;
  PBRMaterial *materials;
  uint model_index;
  uint material_index;
};

struct VertexInput {
  uint vertex_index : SV_VertexID;
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

struct V2PShadow {
  float4 pos : SV_Position;
}

[shader("vertex")]
V2PShadow vertex_shadow_main(VertexInput input) {
  let vertex = pc.vertex_buffer[input.vertex_index];

  let model_to_world = pc.model_matrices[pc.model_index];
  let view_projection_matrix = pc.global_data_buffer.sun_view_projection_matrix;

  V2PShadow output;
  output.pos = mul(view_projection_matrix,
                   mul(model_to_world, float4(vertex.position, 1.0)));

  return output;
}

[shader("vertex")]
FragmentInput vertex_main(VertexInput input) {
  let vertex = pc.vertex_buffer[input.vertex_index];

  let view_projection_matrix = pc.global_data_buffer.view_projection_matrix;
  let sun_view_projection_matrix =
      pc.global_data_buffer.sun_view_projection_matrix;

  let model_to_world = pc.model_matrices[pc.model_index];

  let pos = mul(model_to_world, float4(vertex.position, 1.0));
  let uv = float2(vertex.uv_x, vertex.uv_y);

  let T = normalize(mul((float3x3)model_to_world, vertex.tangent.xyz));
  let N = normalize(mul((float3x3)model_to_world, -vertex.normal));
  let B = cross(N, T);

  FragmentInput output;
  output.color = 1;
  output.pos = mul(view_projection_matrix, pos);
  output.uv = uv;
  output.frag_pos = pos.xyz;
  output.tbn = float3x3(T, B ,N);
  output.sun_space_pos = mul(biasMat, mul(sun_view_projection_matrix, pos));

  return output;
}

struct FragmentInput {
  float4 pos : SV_Position;
  float3 color : COLOR0;
  float2 uv : TEXCOORD0;
  float3 frag_pos;
  float4 sun_space_pos;
  float3x3 tbn;
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

  let material = pc.materials[pc.material_index];

  float3 normal = sample_texture(material.normal_map_id, i.uv).rgb * 2.0 - 1.0;
  normal.y *= -1;
  normal = mul(normal, i.tbn);
  normal = normalize(normal);

  let shadow =
      filter_pcf(i.pos.xy, i.sun_space_pos, pc.global_data_buffer.bias);

  float3 base_color = sample_texture(material.base_color_id, i.uv).xyz;
  float reflectance = 0.5f;

  let ao_roughness_metallic =
      sample_texture(material.ao_roughness_metallic, i.uv).rgb;

  let ao_roughness_metallic_srgb =
      linear_to_srgb(ao_roughness_metallic);

  let ao = ao_roughness_metallic.r;
  // let proughness = ao_roughness_metallic.g;
  let proughness = ao_roughness_metallic_srgb.g;
  let metallic = ao_roughness_metallic_srgb.b;

  float3 f0 = 0.16 * reflectance * reflectance * (1.0 - metallic) +
              base_color * metallic;

  float3 diffuse = (1.0 - metallic) * base_color.rgb;

  float3 n = normal;
  float3 v = normalize(view_pos - frag_pos);
  float3 l = normalize(pc.global_data_buffer.sun_pos); // Directional light
  float3 h = normalize(v + l);
  float NoL = clamp(dot(n, l), 0.0, 1.0);

  float3 frag_color = 0;
  frag_color = saturate((NoL * ao * shadow * pc.global_data_buffer.sun_color) *
               standard_brdf(diffuse, proughness, v, l, n, h, f0, NoL));

  // frag_color = evaluate_ibl(n, v, diffuse, f0, 1.0, roughness);
  frag_color += pc.global_data_buffer.sky_color * ao *
                evaluate_ibl(n, v, diffuse, f0, proughness, pc.global_data_buffer.environment.sh_coeffs);

  // DEBUG
  // float3 r = reflect(-v, n);
  // frag_color = sample_cubemap(ENVIRONMENT_MAP_ID, r, 0).rgb;
  // frag_color = sample_cubemap(ENVIRONMENT_MAP_ID, n, 0).rgb;
  // frag_color = evaluate_specular_ibl(r, proughness);
  // frag_color = irradiance_sh(n, pc.global_data_buffer.environment.sh_coeffs);
  // frag_color = saturate(normal);
  // frag_color = saturate(i.tbn[0]); // Tangent
  // frag_color = saturate(i.tbn[1]); // Bitangent
  // frag_color = saturate(i.tbn[2]); // Normal

  FragmentOutput output;
  output.frag_color = float4(frag_color, 1.0f);

  return output;
}
