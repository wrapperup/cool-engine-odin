package gfx

import vk "vendor:vulkan"

cmd_bind_graphics_pipeline :: #force_inline proc(cmd: vk.CommandBuffer, pipeline: GraphicsPipeline) {
	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, pipeline.layout, 0, 1, &r_ctx.bindless_system.descriptor_set, 0, nil)
	vk.CmdBindPipeline(cmd, .GRAPHICS, pipeline.pipeline)

	r_ctx.current_pipeline = pipeline.common
}

cmd_bind_graphics_pipeline_ptr :: #force_inline proc(cmd: vk.CommandBuffer, pipeline: ^GraphicsPipeline) {
	cmd_bind_graphics_pipeline(cmd, pipeline^)
}

cmd_bind_compute_pipeline :: #force_inline proc(cmd: vk.CommandBuffer, pipeline: ComputePipeline) {
	vk.CmdBindDescriptorSets(cmd, .COMPUTE, pipeline.layout, 0, 1, &r_ctx.bindless_system.descriptor_set, 0, nil)
	vk.CmdBindPipeline(cmd, .COMPUTE, pipeline.pipeline)

	r_ctx.current_pipeline = pipeline.common
}

cmd_bind_compute_pipeline_ptr :: #force_inline proc(cmd: vk.CommandBuffer, pipeline: ^ComputePipeline) {
	cmd_bind_compute_pipeline(cmd, pipeline^)
}


cmd_bind_pipeline :: proc {
	cmd_bind_graphics_pipeline,
	cmd_bind_graphics_pipeline_ptr,
	cmd_bind_compute_pipeline,
	cmd_bind_compute_pipeline_ptr,
}

cmd_push_constants :: #force_inline proc(cmd: vk.CommandBuffer, push_constants: $T, offset: u32 = 0) {
	push_constants := push_constants
	vk.CmdPushConstants(cmd, r_ctx.current_pipeline.layout, r_ctx.current_pipeline.stage_flags, 0, size_of(T), &push_constants)
}

cmd_bind_index_buffer :: #force_inline proc(
	cmd: vk.CommandBuffer,
	buffer: vk.Buffer,
	offset: vk.DeviceSize = 0,
	index_type: vk.IndexType = .UINT32,
) {
	vk.CmdBindIndexBuffer(cmd, buffer, offset, index_type)
}

cmd_draw_indexed :: #force_inline proc(
	cmd: vk.CommandBuffer,
	index_count: u32,
	instance_count: u32 = 1,
	first_index: u32 = 0,
	vertex_offset: i32 = 0,
	first_instance: u32 = 0,
) {
	vk.CmdDrawIndexed(cmd, index_count, instance_count, first_index, vertex_offset, first_instance)
}

RenderingAttachmentInfo :: struct {
	view:        vk.ImageView,
	clear_value: ^vk.ClearValue,
	layout:      vk.ImageLayout,
}

// TODO: this is stupid. there's no need for pointers at all for the clear value.
cmd_begin_rendering :: proc(
	cmd: vk.CommandBuffer,
	area: vk.Extent2D,
	color_attachment: ^RenderingAttachmentInfo = nil,
	depth_attachment: ^RenderingAttachmentInfo = nil,
) {
	vk_color_attachment: vk.RenderingAttachmentInfo
	a_ok := false
	vk_depth_attachment: vk.RenderingAttachmentInfo
	b_ok := false

	if color_attachment != nil {
		vk_color_attachment = init_attachment_info(color_attachment.view, color_attachment.clear_value, color_attachment.layout)
		a_ok = true
	}

	if depth_attachment != nil {
		vk_depth_attachment = init_attachment_info(depth_attachment.view, depth_attachment.clear_value, depth_attachment.layout)
		b_ok = true
	}

	render_info := init_rendering_info(area, a_ok ? &vk_color_attachment : nil, b_ok ? &vk_depth_attachment : nil)
	vk.CmdBeginRendering(cmd, &render_info)
}

cmd_end_rendering :: #force_inline proc(cmd: vk.CommandBuffer) {
	vk.CmdEndRendering(cmd)
}

cmd_dispatch :: #force_inline proc(cmd: vk.CommandBuffer, group_count_x: u32 = 1, group_count_y: u32 = 1, group_count_z: u32 = 1) {
	vk.CmdDispatch(cmd, group_count_x, group_count_y, group_count_z)
}

cmd_copy_buffer :: #force_inline proc(
	cmd: vk.CommandBuffer,
	src_buffer: ^GPUBuffer($T),
	dst_buffer: ^GPUBuffer($U),
	size := 0,
	dst_offset := 0,
	src_offset := 0,
) {
	region := vk.BufferCopy {
		dstOffset = vk.DeviceSize(dst_offset),
		srcOffset = vk.DeviceSize(src_offset),
		size      = vk.DeviceSize(size),
	}

	vk.CmdCopyBuffer(cmd, src_buffer.buffer, dst_buffer.buffer, 1, &region)
}

ImageLayer :: struct {
	mip_level:        int,
	base_array_layer: int,
	layer_count:      int,
}

cmd_copy_buffer_to_image :: #force_inline proc(
	cmd: vk.CommandBuffer,
	src_buffer: ^GPUBuffer($T),
	dst_image: ^GPUImage,
	extent: [3]int,
	offset := [3]int{},
	layer := ImageLayer {
        mip_level = 0,
        base_array_layer = 0,
        layer_count = 1,
    },
    buffer_offset := 0
) {
	copy_region := vk.BufferImageCopy {
		imageSubresource = {
			aspectMask = vk_aspect_of_format(dst_image.format),
			mipLevel = u32(layer.mip_level),
			baseArrayLayer = u32(layer.base_array_layer),
			layerCount = u32(layer.layer_count),
		},
        bufferOffset = cast(vk.DeviceSize)buffer_offset,
		imageExtent = vk.Extent3D{u32(extent.x), u32(extent.y), u32(extent.z)},
		imageOffset = vk.Offset3D{i32(offset.x), i32(offset.y), i32(offset.z)},
	}
	vk.CmdCopyBufferToImage(cmd, src_buffer.buffer, dst_image.image, dst_image.current_layout, 1, &copy_region)
}
