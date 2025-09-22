package game

import vk "vendor:vulkan"

import "gfx"

RenderPass :: struct {
    image_uses: []ImageUse,
    init: proc(this: rawptr),
    run: proc(this: rawptr, cmd: vk.CommandBuffer),
}

RenderGraph :: struct {
    passes: [dynamic]^RenderPass,
    image_resources: map[string]gfx.GPUImage,
}

ImageUse :: struct {
    name: string,
    layout : vk.ImageLayout
}

render_graph_init :: proc(graph: ^RenderGraph) {
    for pass in graph.passes {
        pass->init()
    }
}

render_graph_run :: proc(cmd: vk.CommandBuffer, graph: ^RenderGraph) {
    for pass in graph.passes {
        for &image_use in pass.image_uses {
            image := &graph.image_resources[image_use.name]

            if image.current_layout != image_use.layout {
                gfx.transition_image(cmd, image, image_use.layout)
            }
        }

        pass->run(cmd)
    }
}

render_graph_add_image :: proc(graph: ^RenderGraph, name: string, image: gfx.GPUImage) {
    _, ok := graph.image_resources[name]
    assert(!ok)

    graph.image_resources[name] = image
}
