package game

import "core:fmt"
import "core:math"
import vk "vendor:vulkan"

import "gfx"

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
	dfg_image:               gfx.GPUImage,
	dfg_image_mapped_buffer: gfx.GPUBuffer,
	width, height:           u32,
}


create_dfg_generate_pipeline :: proc(width, height: u32) -> DfgGeneratePass {
	pass := DfgGeneratePass {
		width  = width,
		height = height,
	}

	pass.descriptor_set_layout = gfx.create_descriptor_set_layout(
		{{binding = 0, type = .STORAGE_IMAGE}},
		{.UPDATE_AFTER_BIND_POOL},
		{.COMPUTE},
	)

	gfx.defer_destroy(&gfx.renderer().global_arena, pass.descriptor_set_layout)

	pass.descriptor_set = gfx.allocate_descriptor_set(
		&gfx.renderer().global_descriptor_allocator,
		gfx.renderer().device,
		pass.descriptor_set_layout,
	)

	pass.dfg_image = gfx.create_gpu_image(.R16G16_SFLOAT, {width, height, 1}, {.STORAGE, .TRANSFER_SRC})
	gfx.create_gpu_image_view(&pass.dfg_image, {.COLOR})

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

	pass.pipeline_layout = gfx.create_pipeline_layout_pc("DFG", &pass.descriptor_set_layout, DfgGeneratePassPC, {.COMPUTE})
	pass.pipeline, _ = gfx.create_compute_pipelines("DFG", pass.pipeline_layout, dfg_shader)

	gfx.destroy_shader_module(dfg_shader)

	gfx.defer_destroy(&gfx.renderer().global_arena, pass.pipeline)
	gfx.defer_destroy(&gfx.renderer().global_arena, pass.pipeline_layout)

	// R16G16_SFLOAT = size_of(f32) * 1 (2 components mapped to bytes of float)
	size := width * height * size_of(f32)
	pass.dfg_image_mapped_buffer = gfx.create_buffer(vk.DeviceSize(size), {.TRANSFER_DST}, .GPU_TO_CPU)

	return pass
}

run_dfg_generate_pass :: proc(pass: ^DfgGeneratePass, cmd: vk.CommandBuffer) {
	vk.CmdBindPipeline(cmd, .COMPUTE, pass.pipeline)
	vk.CmdBindDescriptorSets(cmd, .COMPUTE, pass.pipeline_layout, 0, 1, &pass.descriptor_set, 0, nil)

	consts := DfgGeneratePassPC {
		sample_count = 4096,
		multiscatter = false,
	}

	vk.CmdPushConstants(cmd, pass.pipeline_layout, {.COMPUTE}, 0, size_of(DfgGeneratePassPC), &consts)
	vk.CmdDispatch(cmd, pass.width / 16, pass.height / 16, 1)
}
