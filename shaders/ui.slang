import bindless;
import types;

struct UI_Circle {
    Vec2 center;
    f32 radius;
    Vec4 color;
}

struct UI_Rounded_Box {
    Vec2 center;
    f32 radius;
    Vec4 color;
}

struct PushConstants {
  RWImage2D resolved_image;
};

[vk_push_constant]
PushConstants pc;

[numthreads(16, 16, 1)]
[shader("compute")]
void compute_main(Vec3u32 dispatchThreadID: SV_DispatchThreadID) {
  let texel_coord = uint2(dispatchThreadID.xy);

  Vec2u32 size;
  pc.resolved_image.get_dimensions(size.x, size.y);

  let exposure = 3.0f;
  if (texel_coord.x < size.x && texel_coord.y < size.y) {
    var color = pc.resolved_image.load(texel_coord).rgba;

    let circles: UI_Circle[] = {
        { Vec2(10, 2), 20, Vec4(1, 1, 0, 0.5) },
        { Vec2(1920/2, 1080/2), 80, Vec4(1, 1, 1, 1) },
    };

    for (int i = 0; i < 10; i++) {
        let circle = circles[i];

        let d_shadow = sdf_circle(texel_coord, circle.center, circle.radius);
        color = lerp(color, Vec4(0), saturate((-d_shadow/10) + 10/10) * 0.3);

        let d_object = sdf_circle(texel_coord, circle.center, circle.radius);
        color = lerp(color, circle.color, saturate(-d_object));
    }

    pc.resolved_image.store(texel_coord, color);
  }
}

float sdf_circle(Vec2 coord, Vec2 center, f32 radius) {
    return length(center - coord) - radius;
}
