float2 get_world_space_uv(float3 world_pos, float3 world_normal) {
  if (abs(world_normal.x) > 0.5f) {
    return world_pos.yz;
  } else if (abs(world_normal.y) > 0.5f) {
    return world_pos.xz;
  } else {
    return world_pos.xy;
  }
}

float4 get_world_space_tangent(float3 world_normal) {
  if (abs(world_normal.x) > 0.5f) {
    return float4(0.f, 1.f, 0.f, sign(world_normal.x));
  } else if (abs(world_normal.y) > 0.5f) {
    return float4(1.f, 0.f, 0.f, -sign(world_normal.y));
  } else {
    return float4(1.f, 0.f, 0.f, sign(world_normal.z));
  }
}
