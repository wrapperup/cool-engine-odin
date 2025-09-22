package gfx

import vk "vendor:vulkan"

import im "deps:odin-imgui"
import im_vk "deps:odin-imgui/imgui_impl_vulkan"

render_imgui :: proc() {
	im.Render()
}

draw_imgui :: proc(cmd: vk.CommandBuffer, target_image_view: vk.ImageView) {
	color_attachment := init_attachment_info(target_image_view, nil, .GENERAL)
	render_info := init_rendering_info(r_ctx.swapchain.swapchain_extent, &color_attachment, nil)

	vk.CmdBeginRendering(cmd, &render_info)

	im_vk.RenderDrawData(im.GetDrawData(), cmd)

	vk.CmdEndRendering(cmd)
}
