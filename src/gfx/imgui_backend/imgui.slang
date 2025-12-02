public [vk_binding(0, 0)] __DynamicResource Images[];
public [vk_binding(1, 0)] __DynamicResource<__DynamicResourceKind.Sampler> Samplers[];
public [vk_binding(2, 0)] __DynamicResource RWImages[];

struct DrawVert {
    float2 pos;
    float2 uv;
    uint32_t col;
}

struct PushConstants {
	DrawVert* vbuffer;
    float2 scale;
    float2 translation;
    uint64_t image_id;
};

struct CombinedImageId {
    uint32_t image_index;
    uint32_t sampler_index;
    bool rw_image;
};

[vk_push_constant]
PushConstants pc;

struct VertexInput {
  uint32_t vertex_index : SV_VertexID;
};

float4 hex_to_rgba(uint32_t hex) {
    float r = ((hex >> 24) & 0xFF) / 255.0f;
    float g = ((hex >> 16) & 0xFF) / 255.0f;
    float b = ((hex >> 8) & 0xFF) / 255.0f;
    float a = (hex & 0xFF) / 255.0f;

    return float4(r, g, b, a);
}

[shader("vertex")]
FragmentInput vertex_main(VertexInput in) {
    DrawVert vertex = pc.vbuffer[in.vertex_index];

    float4 pos = float4(vertex.pos * pc.scale + pc.translation, 0, 1);
    float2 uv = vertex.uv;
    float4 col = hex_to_rgba(vertex.col);

    return {
        pos,
        uv,
        col,
    };
}

struct FragmentInput {
    float4 pos : SV_Position;
    float2 uv : TEXCOORD0;
    float4 col : COLOR0;
};

struct FragmentOutput {
    float4 col: COLOR0;
};

CombinedImageId decode_combined_image_id(uint64_t packed) {
    uint image_index   = uint(packed & 0xFFFFFFFFull);           // bits 0–31
    uint sampler_index = uint((packed >> 32) & 0x7FFFFFFFull);   // bits 32–62
    bool rw_image      = ((packed >> 63) & 1ull) != 0;           // bit 63
    
    return {
        image_index,
        sampler_index,
        rw_image,
    };
}

[shader("fragment")]
FragmentOutput fragment_main(FragmentInput in) {
    float4 texture_col;

    CombinedImageId image = decode_combined_image_id(pc.image_id);

    Texture2D tex = Images[image.image_index];
    SamplerState sampler = Samplers[image.sampler_index].as<SamplerState>();

    texture_col = tex.Sample(sampler, in.uv);

    float4 col = in.col * texture_col;

    return {
      col,
    };
}
