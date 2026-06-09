import bindless;
import types;

struct DrawVert {
    Vec2 pos;
    Vec2 uv;
    u32  col;
}

struct PushConstants {
    DrawVert *vertex_buffer;
    Vec2 scale;
    Vec2 translate;
    Image2D texture;
    Sampler sampler;
}

[vk_push_constant]
PushConstants pc;

struct VertexInput {
    u32 vertex_id : SV_VertexID;
}

struct FragmentInput {
    Vec4 pos_cs : SV_Position;
    [vk_location(0)] Vec2 uv;
    [vk_location(1)] Vec4 color;
}

Vec4 unpack_srgba(u32 c) {
    return Vec4(
        f32((c >>  0) & 0xff) / 255.0,
        f32((c >>  8) & 0xff) / 255.0,
        f32((c >> 16) & 0xff) / 255.0,
        f32((c >> 24) & 0xff) / 255.0
    );
}

[shader("vertex")]
FragmentInput vertex_main(VertexInput in) {
    let v = pc.vertex_buffer[in.vertex_id];

    FragmentInput o;
    o.pos_cs = Vec4(v.pos * pc.scale + pc.translate, 0.0, 1.0);
    o.uv     = v.uv;
    o.color  = unpack_srgba(v.col);
    return o;
}

struct FragmentOutput {
    [vk_location(0)] Vec4 frag_color : COLOR0;
}

[shader("fragment")]
FragmentOutput fragment_main(FragmentInput in) {
    let tex = pc.texture.sample(pc.sampler, in.uv);
    FragmentOutput o;
    o.frag_color = in.color * tex;
    return o;
}
