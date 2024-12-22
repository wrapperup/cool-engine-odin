import bindless;
import brdf;
import common;
import consts;
import ibl;
import lights;
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
  Mat4x4 *shadow_cascade_matrices;
  u32 model_index;
  u32 material_index;
  u32 num_cascades;
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

[shader("vertex")]
FragmentInput vertex_main(VertexInput input) {
  let vertex = pc.vertex_buffer[input.vertex_index];

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

  let view_projection_matrix = mul(pc.global_data_buffer.projection_matrix, pc.global_data_buffer.view_matrix);

  FragmentInput output;
  output.color = vertex.color.rgb;
  output.pos = view_projection_matrix * pos;
  output.view_pos = view_projection_matrix * pos;
  output.uv = uv;
  output.world_pos = pos;
  output.view_pos = pc.global_data_buffer.view_matrix * pos;
  output.tbn = Mat3x3(T, B, N);

  return output;
}

struct FragmentInput {
  Vec4 pos : SV_Position;
  Vec3 color : COLOR0;
  Vec2 uv : TEXCOORD0;
  Vec4 world_pos;
  Vec4 view_pos;
  Mat3x3 tbn;
  u32 tex_id;
};

struct FragmentOutput {
  [vk_location(0)]
  Vec4 frag_color : COLOR0;
};

[shader("fragment")]
FragmentOutput fragment_main(FragmentInput in) {
  let world_pos = in.world_pos.xyz;
  let view_pos = pc.global_data_buffer.camera_pos;

  let material = pc.materials[pc.material_index];

  Vec2 uv = in.uv;
  // uv = 0;
  if (pc.material_index == 0) {
    uv = get_world_space_uv(world_pos, in.tbn[2]) / 4.f;
  }

  Vec3 normal =
      material.normal_map_id.sample(DEFAULT_SAMPLER_ID, uv).rgb * 2.0 - 1.0;
  normal.y *= -1;
  normal = normal * in.tbn;
  normal = normalize(normal);

  static const f32 FAR = 100;
  static const f32 NEAR = 0.1;

  let segment_dist = (FAR - NEAR) / pc.num_cascades;

  u32 cascade_index = 0;

  for (uint i = 0; i < pc.num_cascades; i++) {
    if ((in.view_pos.z) < -(NEAR + (segment_dist * (i)))) {
      cascade_index = i;
    }
  }

  Vec3 base_color =
      material.base_color_id.sample(DEFAULT_SAMPLER_ID, uv).xyz * in.color;

  // if (cascade_index == 0) {
  //   base_color = Vec3(1, 0, 0);
  // }
  // else if (cascade_index == 1) {
  //   base_color = Vec3(0, 1, 0);
  // }
  // else if (cascade_index == 2) {
  //   base_color = Vec3(0, 0, 1);
  // } else {
  //   base_color = 0;
  // }

  f32 reflectance = 0.5f;

  let ao_roughness_metallic =
      material.ao_roughness_metallic.sample(DEFAULT_SAMPLER_ID, uv).rgb;

  let ao_roughness_metallic_srgb = linear_to_srgb(ao_roughness_metallic);

  let ao = ao_roughness_metallic.r;
  let proughness = ao_roughness_metallic_srgb.g;
  let metallic = ao_roughness_metallic_srgb.b;

  Vec3 f0 = 0.16 * reflectance * reflectance * (1.0 - metallic) +
            base_color * metallic;

  Vec3 diffuse = (1.0 - metallic) * base_color.rgb;

  Vec3 n = normal;
  Vec3 v = normalize(view_pos - world_pos);
  Vec3 l = normalize(pc.global_data_buffer.sun_direction); // Directional light

  f32 sun_NoL = clamp(dot(n, l), 0.0, 1.0);

  let world_to_shadow = pc.shadow_cascade_matrices[cascade_index];
  let shadow_space_pos = BIAS_MAT * (world_to_shadow * in.world_pos);

  let shadow = filter_pcf(in.pos.xy, shadow_space_pos, cascade_index,
                          pc.global_data_buffer.bias, 0, sun_NoL);

  Vec3 frag_color = 0;
  frag_color =
      saturate((min(sun_NoL, min(shadow, ao)) * pc.global_data_buffer.sun_color) *
               standard_bsdf(diffuse, proughness, v, l, n, f0, sun_NoL));

  for (uint i = 0; i < pc.global_data_buffer.environment.num_point_lights;
       i++) {
    let point_light = pc.global_data_buffer.environment.point_lights[i];

    let light_pos = point_light.world_pos;
    let radius = point_light.radius;
    let lumens = point_light.lumens;
    let color = normalize(point_light.color);
    let dist = distance(world_pos, light_pos);

    if (dist <= radius) {
      let pos_to_light = light_pos - world_pos;
      let point_light_l = normalize(pos_to_light);
      let point_light_h = normalize(v + point_light_l);
      let point_light_NoL = clamp(dot(n, point_light_l), 0.0, 1.0);

      let bsdf = standard_bsdf(diffuse, proughness, v, point_light_l, n, f0,
                               point_light_NoL);
      let attenuation =
          get_square_falloff_attenuation(pos_to_light, 1.f / radius);

      frag_color +=
          (bsdf * lumens * attenuation * point_light_NoL) * color * ao;
    }
  }

  frag_color += pc.global_data_buffer.sky_color * ao *
                evaluate_ibl(n, v, diffuse, f0, proughness,
                             pc.global_data_buffer.environment.sh_volume[0]);

  // DEBUG
  // frag_color = base_color;
  // frag_color = 1;
  // let r = reflect(-v, n);
  // frag_color = ENVIRONMENT_MAP_ID.sample_level(ENVIRONMENT_SAMPLER_ID, r,
  // 0).rgb; frag_color =
  // ENVIRONMENT_MAP_ID.sample_level(ENVIRONMENT_SAMPLER_ID, n, 0).rgb;
  // frag_color = evaluate_specular_ibl(r, proughness);
  // frag_color = irradiance_sh(n,
  // pc.global_data_buffer.environment.sh_volume[0]); frag_color = saturate(n);
  // frag_color = saturate(i.tbn[0]); // Tangent
  // frag_color = saturate(i.tbn[1]); // Bitangent
  // frag_color = saturate(i.tbn[2]); // Normal
  // frag_color = saturate(world_pos.xyz);

  FragmentOutput output;
  output.frag_color = Vec4(frag_color, 1.0f);

  return output;
}
