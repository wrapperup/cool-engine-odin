import bindless;
import types;

struct Vertex {
  Vec3 position;
  f32 uv_x;
  Vec3 normal;
  f32 uv_y;
  Vec4 color;
  Vec4 tangent;
};

struct PointLight {
  Vec3 color;
  f32 radius;
  Vec3 world_pos;
  f32 lumens;
}

struct ShCoefficients {
  Vec4 coeffs[9];
}

struct ShCoefficientVolume {
  u32 sh_0_3_id;
  u32 sh_4_7_id;
  u32 sh_8_9_id;
}

struct Environment {
  ShCoefficients *sh_volume;
  PointLight *point_lights;
  u32 num_point_lights;
}

struct CascadeConfig {
  f32 split_dist;
  f32 bias;
  f32 slope_bias;
}

struct GlobalData {
  Mat4x4 view_to_clip;
  Mat4x4 world_to_view;
  Mat4x4* cascades_world_to_shadow;
  CascadeConfig* cascade_configs;
  Vec3 sun_color;
  f32 pad_0;
  Vec3 sky_color;
  f32 pad_1;
  Vec3 camera_pos;
  f32 pad_2;
  Vec3 sun_direction;
  f32 pad_3;
  Environment environment;
};

struct PBRMaterial {
  Tex2D base_color_id;
  Tex2D normal_map_id;
  Tex2D ao_roughness_metallic;
}

Vec3 srgb_to_linear(Vec3 color) { return pow(color, 2.2); }

Vec3 linear_to_srgb(Vec3 color) { return pow(color, 1.0 / 2.2); }
