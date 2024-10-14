package tools

import "core:fmt"
import "core:math"
import vk "vendor:vulkan"

import "../src/gfx"

DfgGeneratePassPC :: struct {
	sample_count: u32,
	multiscatter: b32,
}

DfgGeneratePass :: struct {
	descriptor_set_layout:   vk.DescriptorSetLayout,
	descriptor_set:          vk.DescriptorSet,
	pipeline:                vk.Pipeline,
	pipeline_layout:         vk.PipelineLayout,

	// Resources
	dfg_image:               gfx.AllocatedImage,
	dfg_image_mapped_buffer: gfx.AllocatedBuffer,
}


create_dfg_generate_pipeline :: proc() -> DfgGeneratePass {
	width: u32 = 256
	height: u32 = 256

	pass: DfgGeneratePass

	pass.descriptor_set_layout = gfx.create_descriptor_set_layout(
		[?]gfx.DescriptorBinding{{binding = 0, type = .STORAGE_IMAGE}},
		{.UPDATE_AFTER_BIND_POOL},
		{.COMPUTE},
	)

	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, pass.descriptor_set_layout)

	pass.descriptor_set = gfx.allocate_descriptor_set(
		&gfx.renderer().global_descriptor_allocator,
		gfx.renderer().device,
		pass.descriptor_set_layout,
	)

	pass.dfg_image = gfx.create_image(.R16G16_SFLOAT, {width, height, 1}, {.STORAGE, .TRANSFER_SRC})
	gfx.create_image_view(&pass.dfg_image, {.COLOR})

	// Maybe we can make a nicer abstraction?
	gfx.write_descriptor_set(
		pass.descriptor_set,
		{
			{
				binding      = 0,
				type         = .STORAGE_IMAGE, // We know this
				image_view   = pass.dfg_image.image_view,
				image_layout = .GENERAL,
			},
		},
	)

	dfg_shader, f_ok := gfx.load_shader_module("shaders/out/dfg.spv")
	assert(f_ok, "Failed to load shaders.")

	pass.pipeline_layout = gfx.create_pipeline_layout_pc(&pass.descriptor_set_layout, DfgGeneratePassPC, {.COMPUTE})
	pass.pipeline = gfx.create_compute_pipelines(pass.pipeline_layout, dfg_shader)

	gfx.destroy_shader_module(dfg_shader)

	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, pass.pipeline)
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, pass.pipeline_layout)

	// R16G16_SFLOAT = size_of(f32) * 1 (2 components mapped to bytes of float)
	size := width * height * size_of(f32)
	pass.dfg_image_mapped_buffer = gfx.create_buffer(vk.DeviceSize(size), {.TRANSFER_DST}, .GPU_TO_CPU)

	return pass
}

run_dfg_generate_pass :: proc(pass: ^DfgGeneratePass, cmd: vk.CommandBuffer) {
	vk.CmdBindPipeline(cmd, .COMPUTE, pass.pipeline)
	vk.CmdBindDescriptorSets(cmd, .COMPUTE, pass.pipeline_layout, 0, 1, &pass.descriptor_set, 0, nil)

	width: u32 = 256
	height: u32 = 256

	consts := DfgGeneratePassPC {
		sample_count = 1024,
		multiscatter = false,
	}

	vk.CmdPushConstants(cmd, pass.pipeline_layout, {.COMPUTE}, 0, size_of(DfgGeneratePassPC), &consts)
	vk.CmdDispatch(cmd, width, height, 1)
}
