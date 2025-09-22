package game

import "core:math"
import vk "vendor:vulkan"

import "gfx"

// MAX_ROUGHNESS_LEVELS: u32 : 9
// PREFILTERED_DEFAULT_SIZE: u32 : 1024
//
// PrefilteredCubeMapPushConstants :: struct {
// 	mip_level:    u32,
// 	sample_count: u32,
// }
//
// PrefilteredCubeMapPass :: struct {
// 	descriptor_set_layout:         vk.DescriptorSetLayout,
// 	descriptor_set:                vk.DescriptorSet,
// 	pipeline:                      gfx.ComputePipeline,
//
// 	// Resources
// 	cube_image:                    gfx.GPUImage,
// 	cube_sampler:                  vk.Sampler,
// 	prefilter_image:               gfx.GPUImage,
// 	prefilter_image_views:         [MAX_ROUGHNESS_LEVELS]vk.ImageView,
// 	prefilter_image_mapped_buffer: gfx.GPUBuffer(u8),
// 	width:                         u32,
// 	height:                        u32,
// }
//
//
// create_prefiltered_cubemap_pipeline :: proc(filename: cstring, out_width, out_height: u32) -> PrefilteredCubeMapPass {
// 	pass := PrefilteredCubeMapPass {
// 		width  = out_width,
// 		height = out_height,
// 	}
//
// 	pass.descriptor_set_layout = gfx.create_descriptor_set_layout({
// 		{binding = 0, type = .COMBINED_IMAGE_SAMPLER},
// 		{binding = 1, type = .STORAGE_IMAGE, count = MAX_ROUGHNESS_LEVELS}, // Count is for mipmap views.
// 	},
// 	{.UPDATE_AFTER_BIND_POOL},
// 	{.COMPUTE},
// 	)
//
// 	gfx.defer_destroy(&gfx.renderer().global_arena, pass.descriptor_set_layout)
//
// 	pass.descriptor_set = gfx.allocate_descriptor_set(
// 		&gfx.renderer().global_descriptor_allocator,
// 		gfx.renderer().device,
// 		pass.descriptor_set_layout,
// 	)
//
// 	width, height: u32
// 	pass.cube_image = gfx.load_image_from_file(filename, .D2, .CUBE, &width, &height)
// 	pass.cube_sampler = gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE)
//
// 	if pass.width <= 0 do pass.width = width
// 	if pass.height <= 0 do pass.height = height
//
// 	pass.prefilter_image = gfx.create_gpu_image(
// 		.R32G32B32A32_SFLOAT,
// 		{pass.width, pass.height, 1},
// 		{.STORAGE, .TRANSFER_SRC},
// 		MAX_ROUGHNESS_LEVELS,
// 		6,
// 	)
//
// 	// Maybe we can make a nicer abstraction?
// 	gfx.write_descriptor_set(
// 		pass.descriptor_set,
// 		{
// 			{
// 				binding      = 0,
// 				type         = .COMBINED_IMAGE_SAMPLER, // We know this
// 				image_view   = pass.cube_image.image_view,
// 				sampler      = pass.cube_sampler,
// 				image_layout = .SHADER_READ_ONLY_OPTIMAL,
// 			},
// 		},
// 	)
//
// 	for i in 0 ..< MAX_ROUGHNESS_LEVELS {
// 		dview_info := gfx.init_imageview_create_info(
// 			pass.prefilter_image.format,
// 			pass.prefilter_image.image,
// 			{.COLOR},
// 			.D2_ARRAY,
// 			i,
// 			1,
// 			0,
// 			6,
// 		)
// 		gfx.vk_check(vk.CreateImageView(gfx.r_ctx.device, &dview_info, nil, &pass.prefilter_image_views[i]))
//
// 		gfx.write_descriptor_set(
// 			pass.descriptor_set,
// 			{
// 				{
// 					binding      = 1,
// 					type         = .STORAGE_IMAGE, // We know this
// 					image_view   = pass.prefilter_image_views[i],
// 					image_layout = .GENERAL,
// 					array_index  = i,
// 				},
// 			},
// 		)
// 	}
//
// 	prefilter_shader, f_ok := gfx.load_shader_module("shaders/out/prefilter_env.spv")
// 	assert(f_ok, "Failed to load shaders.")
//
// 	pass.pipeline = gfx.create_compute_pipelines("Environment Prefiler", prefilter_shader, PrefilteredCubeMapPushConstants)
//
// 	gfx.destroy_shader_module(prefilter_shader)
//
// 	// gfx.defer_destroy_pipeline(&gfx.renderer().global_arena, pass.pipeline)
//
// 	size: u32
// 	for level in 0 ..< u32(MAX_ROUGHNESS_LEVELS) {
// 		w := pass.width >> level
// 		h := pass.height >> level
// 		size += w * h * size_of(f32) * 4 * 6 // R32G32B32A32_SFLOAT
// 	}
//
// 	pass.prefilter_image_mapped_buffer = gfx.create_buffer(u8, vk.DeviceSize(size), {.TRANSFER_DST}, .GPU_TO_CPU)
//
// 	return pass
// }
//
// run_prefilter_cubemap_pass :: proc(pass: ^PrefilteredCubeMapPass, cmd: vk.CommandBuffer, sample_count: u32 = 4096) {
// 	gfx.cmd_bind_pipeline(cmd, pass.pipeline)
// 	gfx.CmdBindDescriptorSets(cmd, .COMPUTE, pass.pipeline_layout, 0, 1, &pass.descriptor_set, 0, nil)
//
// 	for level in 0 ..< MAX_ROUGHNESS_LEVELS {
// 		constants := PrefilteredCubeMapPushConstants {
// 			mip_level    = level,
// 			sample_count = sample_count,
// 		}
// 		vk.CmdPushConstants(cmd, pass.pipeline_layout, {.COMPUTE}, 0, size_of(PrefilteredCubeMapPushConstants), &constants)
// 		vk.CmdDispatch(cmd, u32(math.ceil(f32(pass.width >> level) / 16.0)), u32(math.ceil(f32(pass.height >> level) / 16.0)), 6)
// 	}
// }
