package tools

import "core:fmt"
import "core:math"
import "core:time"
import vk "vendor:vulkan"

import "../src/gfx"

MAX_ROUGHNESS_LEVELS: u32 : 6

PrefilteredCubeMapPushConstants :: struct {
	mip_level: u32,
}

PrefilteredCubeMapPass :: struct {
	descriptor_set_layout: vk.DescriptorSetLayout,
	descriptor_set:        vk.DescriptorSet,
	pipeline:              vk.Pipeline,
	pipeline_layout:       vk.PipelineLayout,

	// Resources
	cube_image:            gfx.AllocatedImage,
	cube_sampler:          vk.Sampler,
	prefilter_image:       gfx.AllocatedImage,
}


create_prefiltered_cubemap_pipeline :: proc() -> PrefilteredCubeMapPass {
	pass: PrefilteredCubeMapPass

	pass.descriptor_set_layout = gfx.create_descriptor_set_layout(
		[?]gfx.DescriptorBinding{{binding = 0, type = .COMBINED_IMAGE_SAMPLER}, {binding = 1, type = .STORAGE_IMAGE}},
		{.UPDATE_AFTER_BIND_POOL},
		{.COMPUTE},
	)

	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, pass.descriptor_set_layout)

	pass.descriptor_set = gfx.allocate_descriptor_set(
		&gfx.renderer().global_descriptor_allocator,
		gfx.renderer().device,
		pass.descriptor_set_layout,
	)

	pass.cube_image = gfx.load_image_from_file("assets/ennis.ktx2")
	pass.cube_sampler = gfx.create_sampler(.NEAREST, .CLAMP_TO_EDGE)

	pass.prefilter_image = gfx.create_image(
		.R32G32B32A32_SFLOAT,
		{256, 256, 1},
		{.STORAGE, .TRANSFER_DST},
		1,
		6,
		//flags = {.D2_ARRAY_COMPATIBLE},
	)

	gfx.create_image_view(&pass.prefilter_image, {.COLOR}, 0, .D2_ARRAY)

	name := vk.DebugUtilsObjectNameInfoEXT {
		sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
		objectType   = .IMAGE_VIEW,
		pObjectName  = "poggers!!!!!!!",
		objectHandle = u64(pass.prefilter_image.image_view),
	}

	vk.SetDebugUtilsObjectNameEXT(gfx.r_ctx.device, &name)

	// Maybe we can make a nicer abstraction?
	gfx.write_descriptor_set(
		pass.descriptor_set,
		{
			{
				binding      = 0,
				type         = .COMBINED_IMAGE_SAMPLER, // We know this
				image_view   = pass.cube_image.image_view,
				sampler      = pass.cube_sampler,
				image_layout = .SHADER_READ_ONLY_OPTIMAL,
			},
			{
				binding      = 1,
				type         = .STORAGE_IMAGE, // We know this
				image_view   = pass.prefilter_image.image_view,
				image_layout = .GENERAL,
			},
		},
	)

	prefilter_shader, f_ok := gfx.load_shader_module("shaders/out/prefilter_env.spv")
	assert(f_ok, "Failed to load shaders.")

	pass.pipeline_layout = gfx.create_pipeline_layout_pc(
		&pass.descriptor_set_layout,
		PrefilteredCubeMapPushConstants,
		{.COMPUTE},
	)
	pass.pipeline = gfx.create_compute_pipelines(pass.pipeline_layout, prefilter_shader)

	gfx.destroy_shader_module(prefilter_shader)

	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, pass.pipeline)
	gfx.push_deletion_queue(&gfx.renderer().main_deletion_queue, pass.pipeline_layout)

	return pass
}

run_prefilter_cubemap_pass :: proc(pass: ^PrefilteredCubeMapPass, cmd: vk.CommandBuffer) {
	vk.CmdBindPipeline(cmd, .COMPUTE, pass.pipeline)
	vk.CmdBindDescriptorSets(cmd, .COMPUTE, pass.pipeline_layout, 0, 1, &pass.descriptor_set, 0, nil)

	width := 256
	height := 256

	for level in 0 ..< MAX_ROUGHNESS_LEVELS {
		constants := PrefilteredCubeMapPushConstants {
			mip_level = level,
		}
		vk.CmdPushConstants(cmd, pass.pipeline_layout, {.COMPUTE}, 0, size_of(PrefilteredCubeMapPushConstants), &constants)
		vk.CmdDispatch(cmd, u32(math.ceil(f32(width >> level) / 16.0)), u32(math.ceil(f32(height >> level) / 16.0)), 6)
	}
}
