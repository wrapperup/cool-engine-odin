//
// This is a generated file, do not modify. See src/meta.odin
//

//
// Generated from C:\Repos\odin\cool-engine-odin\src\entity_point_light.odin
//
struct PointLight {
  Vec3 color;
  f32 radius;
  Vec3 world_pos;
  f32 lumens;
};



//
// Generated from C:\Repos\odin\cool-engine-odin\src\gpu_types.odin
//
struct Vertex {
  float3 position;
  f32 uv_x;
  float3 normal;
  f32 uv_y;
  float4 color;
  float4 tangent;
};

struct SkeletonVertexAttribute {
  u8 joints[4];
  f32 weights[4];
};



//
// Generated from C:\Repos\odin\cool-engine-odin\src\renderer.odin
//
struct DrawPushConstants {
  GlobalData* global_data_buffer;
  Vertex* vertex_buffer;
  Mat4x4* model_matrices;
  Material* materials;
  u32 model_index;
  MaterialId material_index;
  u32 num_cascades;
  Image2DArray<f32> shadow_depth;
  SamplerComparison shadow_sampler;
};

struct DrawShadowDepthPushConstants {
  Vertex* vertex_buffer;
  Mat4x4* model_matrices;
  GlobalData* global_data;
  u32 model_index;
  u32 cascade_index;
};

struct SkinningPushConstants {
  Vertex* input_vertex_buffer;
  Vertex* output_vertex_buffer;
  Mat4x4* joint_matrices;
  SkeletonVertexAttribute* attrs;
  u32 vertex_count;
};

struct SkyboxPushConstants {
  Vertex* vertex_buffer;
  GlobalData* global_data_buffer;
};

struct PostProcessingPushConstants {
  RWImage2D resolved_image;
  Image3D<Vec3> tony_mc_mapface;
  Sampler sampler;
};

struct Material {
  Image2D base_color_id;
  Image2D normal_map_id;
  Image2D ao_roughness_metallic_id;
};

struct Environment {
  Mat4x4 world_to_volume;
  Sh_Coefficients* sh_volume;
  PointLight* point_lights;
  u32 num_point_lights;
  ImageCube env_map;
  Image2D dfg;
  Sampler env_sampler;
};

struct CascadeConfig {
  f32 split_dist;
  f32 bias;
  f32 slope_bias;
};

struct GlobalData {
  Environment environment;
  Mat4x4* cascade_world_to_shadows;
  CascadeConfig* cascade_configs;
  Mat4x4 view_to_clip;
  Mat4x4 world_to_view;
  Vec3 sun_color;
  Vec3 sky_color;
  Vec3 camera_pos;
  Vec3 sun_direction;
  Sampler default_sampler;
};



//
// Generated from C:\Repos\odin\cool-engine-odin\src\spherical_harmonics.odin
//
struct Sh_Coefficients {
  Vec4 coeffs[9];
};