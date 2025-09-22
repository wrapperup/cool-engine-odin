package gfx

import vk "vendor:vulkan"

cmd_bind_graphics_pipeline :: proc (cmd: vk.CommandBuffer, pipeline: GraphicsPipeline) {
	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, pipeline.layout, 0, 1, &r_ctx.bindless_system.descriptor_set, 0, nil);
    vk.CmdBindPipeline(cmd, .GRAPHICS, pipeline.pipeline);

    r_ctx.current_pipeline = pipeline.common;
}

cmd_bind_graphics_pipeline_ptr :: proc (cmd: vk.CommandBuffer, pipeline: ^GraphicsPipeline) {
    cmd_bind_graphics_pipeline(cmd, pipeline^)
}

cmd_bind_compute_pipeline :: proc (cmd: vk.CommandBuffer, pipeline: ComputePipeline) {
	vk.CmdBindDescriptorSets(cmd, .COMPUTE, pipeline.layout, 0, 1, &r_ctx.bindless_system.descriptor_set, 0, nil);
    vk.CmdBindPipeline(cmd, .COMPUTE, pipeline.pipeline);

    r_ctx.current_pipeline = pipeline.common;
}

cmd_bind_compute_pipeline_ptr :: proc (cmd: vk.CommandBuffer, pipeline: ^ComputePipeline) {
    cmd_bind_compute_pipeline(cmd, pipeline^)
}


cmd_bind_pipeline :: proc {
    cmd_bind_graphics_pipeline,
    cmd_bind_graphics_pipeline_ptr,
    cmd_bind_compute_pipeline,
    cmd_bind_compute_pipeline_ptr,
}

cmd_push_constants :: proc (cmd: vk.CommandBuffer, push_constants: $T, offset: u32 = 0) {
    push_constants := push_constants
	vk.CmdPushConstants(
		cmd,
		r_ctx.current_pipeline.layout,
		r_ctx.current_pipeline.stage_flags,
		0,
		size_of(T),
		&push_constants,
	);
}

cmd_bind_index_buffer :: proc (
    cmd: vk.CommandBuffer, 
    buffer: vk.Buffer, 
    offset: vk.DeviceSize = 0,
    index_type: vk.IndexType = .UINT32
) {
    vk.CmdBindIndexBuffer(cmd, buffer, offset, index_type);
}

cmd_draw_indexed :: proc (
    cmd: vk.CommandBuffer,
    index_count: u32,
    instance_count: u32 = 1,
    first_index: u32 = 0,
    vertex_offset: i32 = 0,
    first_instance: u32 = 0
) {
    vk.CmdDrawIndexed(cmd, index_count, instance_count, first_index, vertex_offset, first_instance);
}

RenderingInfo :: struct {
    area: vk.Extent2D,

    color_attachment: ^vk.RenderingAttachmentInfo,
    depth_attachment: ^vk.RenderingAttachmentInfo,
}

cmd_begin_rendering :: proc (cmd: vk.CommandBuffer, info: RenderingInfo) {
    render_info := init_rendering_info(info.area, info.color_attachment, info.depth_attachment);
    vk.CmdBeginRendering(cmd, &render_info);
}

cmd_end_rendering :: proc (cmd: vk.CommandBuffer) {
    vk.CmdEndRendering(cmd);
}

cmd_dispatch :: proc (cmd: vk.CommandBuffer, group_count_x: u32 = 1, group_count_y: u32 = 1, group_count_z: u32 = 1) {
    vk.CmdDispatch(cmd, group_count_x, group_count_y, group_count_z);
}

