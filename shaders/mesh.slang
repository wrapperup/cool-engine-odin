import bindless;
import brdf;
import common;
import consts;
import ibl;
import shadows;
import standard_brdf;
import types;
import world_space;

static const Mat4x4 BIAS_MAT = {
  0.5, 0.0, 0.0, 0.5, //
  0.0, 0.5, 0.0, 0.5, //
  0.0, 0.0, 1.0, 0.0, //
  0.0, 0.0, 0.0, 1.0, //
};

struct DrawPushConstants {
  GlobalData *global_data_buffer;
  Vertex *vertex_buffer;
  Mat4x4 *model_matrices;
  PBRMaterial *materials;
  u32 model_index;
  u32 material_index;
};

struct VertexInput {
  u32 vertex_index : SV_VertexID;
};

struct PbrMaterialParams {
  Vec4 base_color;
  Vec4 emissive;
  f32 metallic;
  f32 roughness;
  f32 reflectance;
  f32 ambient_occlussion;
}

[vk_push_constant]
DrawPushConstants pc;

struct V2PShadow {
  Vec4 pos : SV_Position;
}

[shader("vertex")]
V2PShadow vertex_shadow_main(VertexInput input) {
  let vertex = pc.vertex_buffer[input.vertex_index];

  let model_to_world = pc.model_matrices[pc.model_index];
  let view_projection_matrix = pc.global_data_buffer.sun_view_projection_matrix;

  V2PShadow output;
  output.pos = view_projection_matrix * (model_to_world * Vec4(vertex.position, 1.0));

  return output;
}

[shader("vertex")]
FragmentInput vertex_main(VertexInput input) {
  let vertex = pc.vertex_buffer[input.vertex_index];

  let view_projection_matrix = pc.global_data_buffer.view_projection_matrix;
  let sun_view_projection_matrix =
      pc.global_data_buffer.sun_view_projection_matrix;

  let model_to_world = pc.model_matrices[pc.model_index];

  let pos = model_to_world * Vec4(vertex.position, 1.0);
  let uv = Vec2(vertex.uv_x, vertex.uv_y);

  let N = normalize((Mat3x3)model_to_world * -vertex.normal);
  var tangent = vertex.tangent;
  if (pc.material_index == 0) {
    tangent = get_world_space_tangent(N);
  }

  let T = normalize((Mat3x3)model_to_world * tangent.xyz);
  let B = cross(N, T) * tangent.w;

  FragmentInput output;
  output.color = vertex.color.rgb;
  output.pos = view_projection_matrix * pos;
  output.uv = uv;
  output.world_pos = pos.xyz;
  output.tbn = Mat3x3(T, B, N);
  output.sun_space_pos = BIAS_MAT * (sun_view_projection_matrix * pos);

  return output;
}

struct FragmentInput {
  Vec4 pos : SV_Position;
  Vec3 color : COLOR0;
  Vec2 uv : TEXCOORD0;
  Vec3 world_pos;
  Vec4 sun_space_pos;
  Mat3x3 tbn;
  u32 tex_id;
};

struct FragmentOutput {
  [vk_location(0)]
  Vec4 frag_color : COLOR0;
};

[shader("fragment")]
FragmentOutput fragment_main(FragmentInput i) {
  Vec3 world_pos = i.world_pos;
  Vec3 view_pos = pc.global_data_buffer.camera_pos;

  let material = pc.materials[pc.material_index];

  Vec2 uv = i.uv;
  // uv = 0;
  if (pc.material_index == 0) {
    uv = get_world_space_uv(world_pos, i.tbn[2]) / 4.f;
  }

  Vec3 normal = material.normal_map_id.sample(DEFAULT_SAMPLER_ID, uv).rgb * 2.0 - 1.0;
  normal.y *= -1;
  normal = normal * i.tbn;
  normal = normalize(normal);

  let shadow =
      filter_pcf(i.pos.xy, i.sun_space_pos, pc.global_data_buffer.bias);

  Vec3 base_color = material.base_color_id.sample(DEFAULT_SAMPLER_ID, uv).xyz * i.color;
  // base_color = saturate(world_pos/10.f);
  f32 reflectance = 0.5f;

  let ao_roughness_metallic = material.ao_roughness_metallic.sample(DEFAULT_SAMPLER_ID, uv).rgb;

  let ao_roughness_metallic_srgb = linear_to_srgb(ao_roughness_metallic);

  let ao = ao_roughness_metallic.r;
  // let proughness = ao_roughness_metallic.g;
  let proughness = ao_roughness_metallic_srgb.g;
  let metallic = ao_roughness_metallic_srgb.b;

  Vec3 f0 = 0.16 * reflectance * reflectance * (1.0 - metallic) +
              base_color * metallic;
  Vec3 f90 = saturate(dot(f0, Vec3(50.0 * 0.33)));

  Vec3 diffuse = (1.0 - metallic) * base_color.rgb;

  Vec3 n = normal;
  Vec3 v = normalize(view_pos - world_pos);
  Vec3 l = normalize(pc.global_data_buffer.sun_pos); // Directional light
  Vec3 h = normalize(v + l);
  f32 NoL = clamp(dot(n, l), 0.0, 1.0);

  Vec3 frag_color = 0;
  frag_color =
      saturate((NoL * ao * shadow * pc.global_data_buffer.sun_color) *
               standard_brdf(diffuse, proughness, v, l, n, h, f0, f90, NoL));

  // frag_color = evaluate_ibl(n, v, diffuse, f0, 1.0, roughness);
  frag_color += pc.global_data_buffer.sky_color * ao *
                evaluate_ibl(n, v, diffuse, f0, proughness,
                             pc.global_data_buffer.environment.sh_volume[0]);

  // DEBUG
  // let r = reflect(-v, n);
  // frag_color = sample_cubemap(ENVIRONMENT_MAP_ID, r, 0).rgb;
  // frag_color = sample_cubemap(ENVIRONMENT_MAP_ID, n, 0).rgb;
  // frag_color = evaluate_specular_ibl(r, proughness);
  // frag_color = irradiance_sh(n, pc.global_data_buffer.environment.sh_volume[0]);
  // frag_color = saturate(n);
  // frag_color = saturate(i.tbn[0]); // Tangent
  // frag_color = saturate(i.tbn[1]); // Bitangent
  // frag_color = saturate(i.tbn[2]); // Normal
  // frag_color = saturate(world_pos.xyz);

  FragmentOutput output;
  output.frag_color = Vec4(frag_color, 1.0f);

  return output;
}
