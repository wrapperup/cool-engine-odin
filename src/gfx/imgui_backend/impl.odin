package gfx_imgui

import gfx "../"
import "base:intrinsics"
import "core:mem"
import im "deps:odin-imgui"
import vk "vendor:vulkan"

IMGUI_PROGRAM_SPV :: #load("./imgui.spv")

BackendData :: struct {
	graphics_pipeline: gfx.GraphicsPipeline,
	vbuffer:           gfx.GPUBuffer(im.DrawVert),
	ibuffer:           gfx.GPUBuffer(im.DrawIdx),
	font_sheet:        gfx.ImageId,
	font_sampler:      gfx.SamplerId,
}

PushConstants :: struct {
	vbuffer:     gfx.GPUPtr(im.DrawVert),
	scale:       [2]f32,
	translation: [2]f32,
	image_id:    gfx.CombinedImageId,
}

init :: proc() -> bool {
	io := im.GetIO()
	assert(io.BackendRendererUserData == nil)

	backend_data := new(BackendData)
	io.BackendRendererUserData = backend_data
	io.BackendRendererName = "imgui_impl_gfx"
	io.BackendFlags |= {.RendererHasVtxOffset, .RendererHasViewports}

	shader, ok := gfx.load_shader_module_from_bytes(IMGUI_PROGRAM_SPV)
	assert(ok)

	backend_data.graphics_pipeline = gfx.create_graphics_pipeline(
		name = "imgui_impl_gfx_graphics_pipeline",
		shader = shader,
		input_topology = .TRIANGLE_LIST,
		polygon_mode = .FILL,
		front_face = .COUNTER_CLOCKWISE,
		blend_mode = .Alpha,
        push_constants = PushConstants,
	)

	pixels: ^u8
	width: i32
	height: i32

	im.FontAtlas_GetTexDataAsRGBA32(io.Fonts, &pixels, &width, &height)

	// TODO: Maybe just combine these two operations, is there any reason _not_ to just have this be a
	// bindless first API?
	font_sheet_image := gfx.create_image(.R8G8B8A8_UNORM, {u32(width), u32(height), 1}, {.SAMPLED, .TRANSFER_DST})
	backend_data.font_sheet = gfx.add_image(font_sheet_image)

    font_sheet_size := width * height * 4 * size_of(u8)
    pixels_slice := (cast([^]u8)pixels)[:font_sheet_size]

    font_staging_buffer := gfx.create_buffer(u8, font_sheet_size, .Staging, name = "imgui_impl_font_sheet_staging_buffer")
    gfx.write_buffer_slice(&font_staging_buffer, pixels_slice)

    {
        cmd := gfx.immediate_submit()
        gfx.transition_image(cmd, &font_sheet_image, .TRANSFER_DST_OPTIMAL)
        gfx.cmd_copy_buffer_to_image(cmd, &font_staging_buffer, &font_sheet_image, {int(width), int(height), 1})
        gfx.transition_image(cmd, &font_sheet_image, .GENERAL)
    }

    font_sampler := gfx.create_sampler()
    backend_data.font_sampler = gfx.add_sampler(font_sampler)

    font_combined_id := gfx.CombinedImageId {
        rw_image = false,
        image_id = backend_data.font_sheet,
        sampler_id = backend_data.font_sampler,
    }

    im.FontAtlas_SetTexID(io.Fonts, transmute(rawptr)font_combined_id)

	return true
}

render_draw_data :: proc(draw_data: ^im.DrawData, cmd: vk.CommandBuffer, image: ^gfx.GPUImage) {
	fb_width := cast(i32)(draw_data.DisplaySize.x * draw_data.FramebufferScale.x)
	fb_height := cast(i32)(draw_data.DisplaySize.y * draw_data.FramebufferScale.y)

	if fb_width <= 0 || fb_height <= 0 {
		return
	}

	bd := get_backend_data()
	pipeline := bd.graphics_pipeline

	if draw_data.TotalVtxCount > 0 {
		new_vertex_len := cast(int)draw_data.TotalVtxCount
		new_vertex_size := cast(vk.DeviceSize)(new_vertex_len * size_of(im.DrawVert))
		new_index_len := cast(int)draw_data.TotalIdxCount
		new_index_size := cast(vk.DeviceSize)new_index_len * size_of(im.DrawIdx)

		if bd.vbuffer.info.size < new_vertex_size {
			if bd.vbuffer.buffer != 0 {
				gfx.destroy_buffer(bd.vbuffer)
			}
			bd.vbuffer = gfx.create_buffer(im.DrawVert, new_index_len, name = "imgui_impl_gfx_vertex_buffer")

            assert(bd.vbuffer.info.size != 0)
		}

		if bd.ibuffer.info.size < new_index_size {
			if bd.ibuffer.buffer != 0 {
				gfx.destroy_buffer(bd.ibuffer)
			}
			bd.ibuffer = gfx.create_buffer(im.DrawIdx, new_index_len, .Index, name = "imgui_impl_gfx_index_buffer")

            assert(bd.ibuffer.info.size != 0)
		}

        arena := gfx.frame_arena()

		vstaging := gfx.create_buffer(im.DrawVert, new_vertex_len, .Staging, name = "imgui_impl_gfx_vertex_staging_buffer")
		gfx.defer_destroy(arena, vstaging)

		istaging := gfx.create_buffer(im.DrawIdx, new_index_len, .Staging, name = "imgui_impl_gfx_index_staging_buffer")
		gfx.defer_destroy(arena, istaging)

		vtx_dst := cast(^im.DrawVert)vstaging.info.pMappedData
		idx_dst := cast(^im.DrawIdx)istaging.info.pMappedData

		for i in 0 ..< draw_data.CmdLists.Size {
			data := cast([^]^im.DrawList)draw_data.CmdLists.Data
			it := data[i]
			intrinsics.mem_copy(vtx_dst, it.VtxBuffer.Data, it.VtxBuffer.Size * size_of(im.DrawVert))
			intrinsics.mem_copy(idx_dst, it.IdxBuffer.Data, it.IdxBuffer.Size * size_of(im.DrawIdx))
			vtx_dst = mem.ptr_offset(vtx_dst, it.VtxBuffer.Size)
			idx_dst = mem.ptr_offset(idx_dst, it.IdxBuffer.Size)
		}

		gfx.cmd_copy_buffer(cmd, &vstaging, &bd.vbuffer, new_vertex_len)
		gfx.cmd_copy_buffer(cmd, &istaging, &bd.ibuffer, new_index_len)
	}

	gfx.cmd_bind_pipeline(cmd, bd.graphics_pipeline)

	if draw_data.TotalVtxCount > 0 {
		gfx.cmd_bind_index_buffer(cmd, bd.ibuffer.buffer, index_type = .UINT16)
	}

	viewport: vk.Viewport
	viewport.width = cast(f32)fb_width
	viewport.height = cast(f32)fb_height
	viewport.maxDepth = 1.0
	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scale: [2]f32 = {2.0 / draw_data.DisplaySize.x, 2.0 / draw_data.DisplaySize.y}
	translation: [2]f32 = {-1.0 - draw_data.DisplayPos.x * scale[0], -1.0 - draw_data.DisplayPos.y * scale[1]}

	clip_off := draw_data.DisplayPos
	clip_scale := draw_data.FramebufferScale

	gfx.cmd_begin_rendering(
		cmd,
		area = gfx.r_ctx.swapchain.swapchain_extent,
		color_attachment = &{view = image.image_view, layout = .GENERAL},
	)

	global_vtx_offset: i32
	global_idx_offset: i32
	for cmd_list_i in 0 ..< draw_data.CmdLists.Size {
		cmd_list := (cast([^]^im.DrawList)draw_data.CmdLists.Data)[cmd_list_i]
		for pcmd_i in 0 ..< cmd_list.CmdBuffer.Size {
			pcmd := (cast([^]im.DrawCmd)cmd_list.CmdBuffer.Data)[pcmd_i]

			clip_min := im.Vec2{(pcmd.ClipRect.x - clip_off.x) * clip_scale.x, (pcmd.ClipRect.y - clip_off.y) * clip_scale.y}

			clip_max := im.Vec2{(pcmd.ClipRect.z - clip_off.x) * clip_scale.x, (pcmd.ClipRect.w - clip_off.y) * clip_scale.y}

			if clip_min.x < 0.0 {
				clip_min.x = 0.0
			}
			if clip_min.y < 0.0 {
				clip_min.y = 0.0
			}
			if clip_max.x > cast(f32)fb_width {
				clip_max.x = cast(f32)fb_width
			}
			if clip_max.y > cast(f32)fb_height {
				clip_max.y = cast(f32)fb_height
			}
			if clip_max.x <= clip_min.x || clip_max.y <= clip_min.y {
				continue
			}

			scissor: vk.Rect2D
			scissor.offset.x = cast(i32)clip_min.x
			scissor.offset.y = cast(i32)clip_min.y
			scissor.extent.width = cast(u32)(clip_max.x - clip_min.x)
			scissor.extent.height = cast(u32)(clip_max.y - clip_min.y)
			vk.CmdSetScissor(cmd, 0, 1, &scissor)

			gfx.cmd_push_constants(
				cmd,
				PushConstants {
					vbuffer = bd.vbuffer.ptr,
					translation = translation,
					scale = scale,
					image_id = transmute(gfx.CombinedImageId)pcmd.TextureId,
				},
			)

			index_offset: u32 = cast(u32)(cast(i32)pcmd.IdxOffset + global_idx_offset)
			vertex_offset: i32 = cast(i32)pcmd.VtxOffset + global_vtx_offset
			gfx.cmd_draw_indexed(cmd, pcmd.ElemCount, 1, index_offset, vertex_offset, 0)
		}

		global_idx_offset += cmd_list.IdxBuffer.Size
		global_vtx_offset += cmd_list.VtxBuffer.Size
	}

	gfx.cmd_end_rendering(cmd)

	scissor := vk.Rect2D{{0, 0}, {cast(u32)fb_width, cast(u32)fb_height}}
	vk.CmdSetScissor(cmd, 0, 1, &scissor)
}


get_backend_data :: proc() -> ^BackendData {
	if im.GetCurrentContext() != nil {
		return cast(^BackendData)im.GetIO().BackendRendererUserData
	}

	return nil
}

shutdown :: proc() {
	backend_data := get_backend_data()

	gfx.destroy_buffer(backend_data.vbuffer)
	gfx.destroy_buffer(backend_data.ibuffer)
	// gfx.destroy_image(backend_data.font_sheet) // TODO: Implement this in bindless.
	// gfx.destroy_sampler(&backend_data.font_sampler) // TODO: Same as above.
}
