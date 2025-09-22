package game

import vk "vendor:vulkan"
import "gfx"

OpaquePass :: struct {
    using render_pass:    RenderPass,
    mesh_pipeline:        ^gfx.GraphicsPipeline,
}
