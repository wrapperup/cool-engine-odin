package gfx_imgui

import gfx "../"
import im "deps:odin-imgui"

GfxImgui :: struct {
    raster_pipeline: gfx.GraphicsPipeline,
    vbuffer: gfx.GPUBuffer(im.DrawVert),
    ibuffer: gfx.GPUBuffer(im.DrawIdx),
    font_sheet: gfx.ImageId,
    font_sampler: gfx.SamplerId,
}

gfx_imgui_init :: proc() {
    
}
