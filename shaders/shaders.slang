struct VertexInput {
  uint vertex_index : SV_VertexID;
  uint instance_id : SV_InstanceID;
};

struct V2P {
  float4 pos : SV_Position;
  float3 color : COLOR0;
  float2 uv : TEXCOORD0;
  float3 normal;
  float3 frag_pos;
  float4 sun_space_pos;
};

struct V2PShadow {
  float4 pos : SV_Position;
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
}

struct GPUDrawPushConstants {
  GlobalData *global_data_buffer;
  Vertex *vertex_buffer;
  float4x4 *model_matrices;
};

[vk_binding(0, 0)]
Sampler2D<float> ShadowDepthSampler;

[vk_binding(1, 0)]
Sampler2D TestTextureSampler;

[vk_push_constant]
ConstantBuffer<GPUDrawPushConstants> pc;

static const float4x4 biasMat = {
  0.5, 0.0, 0.0, 0.5, //
  0.0, 0.5, 0.0, 0.5, //
  0.0, 0.0, 1.0, 0.0, //
  0.0, 0.0, 0.0, 1.0, //
};

static const float3 fake_light = { 0.0976, 0.9759, 0.1952 };

[shader("vertex")]
V2PShadow vertex_shadow_main(VertexInput input) {
  let vertex = pc.vertex_buffer[input.vertex_index];

  let view_projection_matrix = pc.global_data_buffer.sun_view_projection_matrix;

  V2PShadow output;
  output.pos =
      mul(view_projection_matrix, mul(pc.model_matrices[input.instance_id],
                                      float4(vertex.position, 1.0)));

  return output;
}

[shader("fragment")]
PSOutput fragment_shadow_main(V2PShadow input) {
  PSOutput output;
  return output;
}

float shadow_calc(float4 shadow_coord, float2 offset = 0.0) {
  // perform perspective divide
  float3 proj_coords = shadow_coord.xyz / shadow_coord.w;

  // float closest_depth = ShadowDepthSampler.Sample(proj_coords.xy + offset);
  // float current_depth = proj_coords.z;

  // float shadow = current_depth - pc.global_data_buffer.bias > closest_depth ?
  // 0.0 : 1.0; float4 shadow = ShadowDepthSampler.GatherCmp(proj_coords.xy +
  // offset, proj_coords.z - pc.global_data_buffer.bias); return (shadow.x +
  // shadow.y + shadow.z + shadow.w) / 4.f;

  let shadow = ShadowDepthSampler.SampleCmpLevelZero(
      proj_coords.xy + offset, proj_coords.z - pc.global_data_buffer.bias);

  // let shadow = ShadowDepthSampler.GatherCmp(
  //     proj_coords.xy + offset,
  //     proj_coords.z - pc.global_data_buffer.bias,
  //     {1, 0},
  //     {-1, 0},
  //     {0, 1},
  //     {0, -1},
  //   );

  return shadow;
}

// 9 imad (+ 6 iops with final shuffle) -- https://vkguide.dev
uint3 pcg_3d(uint3 v) {

  v = v * 1664525u + 1013904223u;

  v.x += v.y * v.z;
  v.y += v.z * v.x;
  v.z += v.x * v.y;

  v ^= v >> 16u;

  v.x += v.y * v.z;
  v.y += v.z * v.x;
  v.z += v.x * v.y;

  return v;
}

float filter_pcf(float2 screen_pos, float4 shadow_coord) {
  int2 texDim;
  ShadowDepthSampler.GetDimensions(texDim.x, texDim.y);
  float scale = 1.5;
  float dx = scale * 1.0 / float(texDim.x);
  float dy = scale * 1.0 / float(texDim.y);

  float shadow_factor = 0.0;
  int count = 0;
  int range = 2;

  float3 proj_coords = shadow_coord.xyz / shadow_coord.w;

  proj_coords = proj_coords;

  uint4 u = uint4(uint2(screen_pos), uint(screen_pos.x) ^ uint(screen_pos.y),
                  uint(screen_pos.x) + uint(screen_pos.y));
  float3 rand = pcg_3d(u.xyz);
  rand = normalize(rand);

  float2 dirA = normalize(rand.xy);
  float2 dirB = normalize(float2(-dirA.y, dirA.x));

  dirA *= dx;
  dirB *= dy;

  float current_depth = proj_coords.z;

  for (int x = -range; x <= range; x++) {
    for (int y = -range; y <= range; y++) {
      shadow_factor += shadow_calc(shadow_coord, dirA * x + dirB * y);
      count++;
    }
  }

  return shadow_factor / count;
}

float3 specular(float3 frag_pos, float spec_strength, float3 light_dir,
                float shininess, float3 light_color, float3 view_pos,
                float3 normal) {
  float3 view_dir = normalize(view_pos - frag_pos);
  float3 reflect_dir = reflect(-light_dir, normal);

  float spec = pow(max(dot(view_dir, reflect_dir), 0.0), shininess);
  float3 specular = spec_strength * spec;

  return specular;
}

[shader("vertex")]
V2P vertex_main(VertexInput input) {
  let vertex = pc.vertex_buffer[input.vertex_index];

  let view_projection_matrix = pc.global_data_buffer.view_projection_matrix;

  V2P output;
  output.pos =
      mul(view_projection_matrix, mul(pc.model_matrices[input.instance_id],
                                      float4(vertex.position, 1.0)));
  output.normal =
      mul(pc.model_matrices[input.instance_id], float4(vertex.normal, 0.0)).xyz;
  output.uv = float2(vertex.uv_x, vertex.uv_y);
  output.frag_pos = vertex.position;

  let light_contrib = dot(fake_light, output.normal);

  // output.color = vertex.color.xyz;
  let color_select = input.instance_id % 3;
  switch (color_select) {
  case 0:
    output.color = lerp(float3(1, 0.24, 0.32), float3(1, 0.75, 0.70),
                        saturate(light_contrib));
    break;
  case 1:
    output.color = lerp(float3(0.24, 0.75, 0.32), float3(0.75, 1, 0.70),
                        saturate(light_contrib));
    break;
  case 2:
    output.color = lerp(float3(0.32, 0.24, 0.75), float3(0.7, 0.75, 1),
                        saturate(light_contrib));
  }
  // output.color = 1.f - ShadowDepthSampler.Sample(float2(0.5, 0.5)) * 100.0;

  let sun_view_projection_matrix =
      pc.global_data_buffer.sun_view_projection_matrix;

  output.sun_space_pos =
      mul(biasMat, mul(sun_view_projection_matrix,
                       mul(pc.model_matrices[input.instance_id],
                           float4(vertex.position, 1.0))));

  return output;
}

[shader("fragment")]
PSOutput fragment_main(V2P input) {
  PSOutput output;
  let coord = float4(input.pos.x / 1700, input.pos.y / 900, 0.0, 1.0);
  // let shadow = shadow_calc(input.sun_space_pos);
  let shadow = filter_pcf(input.pos.xy, input.sun_space_pos);
  let normal = normalize(input.normal);
  input.color = 1.f;

  output.frag_color =
      float4(lerp(input.color * pc.global_data_buffer.sun_color,
                  input.color * pc.global_data_buffer.sky_color, 1.0 - shadow),
             1.0);
  // output.frag_color = shadow;
  // output.frag_color = float4(input.color, 1.0);
  // output.frag_color = input.sun_space_pos.z;

  let view_pos = pc.global_data_buffer.camera_pos;
  let light_pos = pc.global_data_buffer.sun_pos;

  let light_dir = normalize(light_pos - input.frag_pos);

  let specular_val = specular(input.frag_pos, 0.5 * shadow, light_dir, 32.f,
                              1.0, view_pos, normal);

  output.frag_color += float4(specular_val, 1.0);
  output.frag_color *= TestTextureSampler.Sample(input.uv);

  return output;
}

