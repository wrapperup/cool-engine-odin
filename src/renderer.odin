package game

import "core:fmt"
import "core:image"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:os/os2"
import "core:time"

import sp "deps:odin-slang/slang"
import vk "vendor:vulkan"

import "gfx"

// TODO: Make this into proper assets?
MaterialId :: u32

NUM_CASCADES: u32 : 3

@(private = "file")
GPUPtr :: gfx.GPUPtr
@(private = "file")
ImageId :: gfx.ImageId
@(private = "file")
SamplerId :: gfx.SamplerId

@(shader_shared)
GPUDrawPushConstants :: struct {
	global_data_buffer: GPUPtr(GPUGlobalData),
	vertex_buffer:      GPUPtr(Vertex),
	model_matrices:     GPUPtr(Mat4x4),
	materials:          GPUPtr(GPUMaterial),
	model_index:        u32,
	material_index:     MaterialId,
	num_cascades:       u32,
	shadow_depth:       ImageId `Image2DArray<f32>`,
	shadow_sampler:     gfx.SamplerId `SamplerComparison`,
}

@(shader_shared)
GPUDrawShadowDepthPushConstants :: struct {
	vertex_buffer:  GPUPtr(Vertex),
	model_matrices: GPUPtr(Mat4x4),
	global_data:    GPUPtr(GPUGlobalData),
	model_index:    u32,
	cascade_index:  u32,
}

@(shader_shared)
GPUSkinningPushConstants :: struct {
	input_vertex_buffer:  GPUPtr(Vertex),
	output_vertex_buffer: GPUPtr(Vertex),
	joint_matrices:       GPUPtr(Mat4x4),
	attrs:                GPUPtr(SkeletonVertexAttribute),
	vertex_count:         u32,
}

@(shader_shared)
GPUSkyboxPushConstants :: struct {
	vertex_buffer:      GPUPtr(Vertex),
	global_data_buffer: GPUPtr(GPUGlobalData),
}

@(shader_shared)
GPUPostProcessingPushConstants :: struct {
	resolved_image:  ImageId `RWImage2D`,
	tony_mc_mapface: ImageId `Image3D<Vec3>`,
	sampler:         SamplerId `Sampler`,
}

@(shader_shared)
GPUMaterial :: struct {
	base_color_id:            ImageId `Image2D`,
	normal_map_id:            ImageId `Image2D`,
	ao_roughness_metallic_id: ImageId `Image2D`,
}

@(shader_shared)
GPUEnvironment :: struct {
	world_to_volume:  Mat4x4,
	sh_volume:        GPUPtr(Sh_Coefficients),
	point_lights:     GPUPtr(GPUPointLight),
	num_point_lights: u32,
	env_map:          ImageId `ImageCube`,
	dfg:              ImageId `Image2D`,
	env_sampler:      SamplerId `Sampler`,
}

@(shader_shared)
GPUCascadeConfig :: struct {
	split_dist: f32,
	bias:       f32,
	slope_bias: f32,
}

@(shader_shared)
GPUGlobalData :: struct #max_field_align(16) {
	environment:              GPUEnvironment,
	cascade_world_to_shadows: GPUPtr(Mat4x4),
	cascade_configs:          GPUPtr(GPUCascadeConfig),
	view_to_clip:             Mat4x4,
	world_to_view:            Mat4x4,
	sun_color:                Vec3,
	sky_color:                Vec3,
	camera_pos:               Vec3,
	sun_direction:            Vec3,
	default_sampler:          SamplerId `Sampler`,
}

RenderState :: struct {
	frame_data:                      [gfx.FRAME_OVERLAP]GameFrameData,

	// Bindless textures, etc
	global_uniform_data:             GPUGlobalData,
	scene_resources:                 struct {
		materials:          [dynamic]GPUMaterial,
		materials_buffer:   gfx.GPUBuffer(GPUMaterial),
		point_lights:       [256]GPUPointLight,
		point_light_buffer: gfx.GPUBuffer(GPUPointLight),
	},
	temp_resources:                  struct {
		tony_mc_mapface_id:      ImageId,
		dfg_id:                  ImageId,
		env_id:                  ImageId,
		default_sampler_id:      SamplerId,
		shadow_depth_sampler_id: SamplerId,
		env_sampler_id:          SamplerId,
		resolved_image_id:       ImageId,
	},
	shader_manager:                  ShaderManager,
	global_session:                  ^sp.IGlobalSession,

	// Mesh pipelines
	mesh_pipeline:                   ^gfx.GraphicsPipeline,
	model_matrices:                  [dynamic]Mat4x4,

	// Skeletal mesh pipelines
	skinning_pipeline:               ^gfx.ComputePipeline,

	// Shadow pipelines
	mesh_shadow_pipeline:            ^gfx.GraphicsPipeline,
	shadow_depth_image:              gfx.GPUImage,
	shadow_depth_image_id:           ImageId,
	shadow_depth_attach_image_views: [NUM_CASCADES]vk.ImageView,
	cascade_world_to_shadows:        [NUM_CASCADES]Mat4x4,
	cascade_configs:                 [NUM_CASCADES]GPUCascadeConfig,

	// Tonemapper pipelines
	tonemapper_pipeline:             ^gfx.ComputePipeline,

	// Skybox pipelines
	skybox_pipeline:                 ^gfx.GraphicsPipeline,
	skybox_mesh:                     GPUMeshBuffers,
	draw_skybox:                     bool,

	// UI
	ui_pass:                         UIPass,
	ui_state:                        UIState,
}

GameFrameData :: struct {
	global_uniform_buffer:   gfx.GPUBuffer(GPUGlobalData),
	model_matrices_buffer:   gfx.GPUBuffer(Mat4x4),
	cascade_matrices_buffer: gfx.GPUBuffer(Mat4x4),
	cascade_configs_buffer:  gfx.GPUBuffer(GPUCascadeConfig),
	mesh_draws:              [dynamic]MeshDraw,
	skel_instances:          [dynamic]^SkeletalMeshInstance,
}

GPU_Font_Instance :: struct {
	pos_min: Vec2,
	pos_max: Vec2,
	uv_min:  Vec2,
	uv_max:  Vec2,
	color:   Vec4,
}

current_frame_game :: proc() -> ^GameFrameData {
	return &game.render_state.frame_data[gfx.current_frame_index()]
}

add_material :: proc(material: GPUMaterial) -> MaterialId {
	scene_resources := &game.render_state.scene_resources
	material_id := MaterialId(len(scene_resources.materials))

	append(&scene_resources.materials, material)

	gfx.staging_write_buffer_slice(&scene_resources.materials_buffer, scene_resources.materials[:])

	return material_id
}

//// INITIALIZATION
init_game_renderer :: proc() {
	init_shadow_maps()
	init_test_resources()
	init_test_materials()
	init_pipelines()
	init_buffers()
}

init_shadow_maps :: proc() {
	extent := vk.Extent3D{game.config.shadow_map_size, game.config.shadow_map_size, 1}

	game.render_state.shadow_depth_image = gfx.create_gpu_image(
		.D32_SFLOAT,
		extent,
		{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
		array_layers = NUM_CASCADES,
	)
	gfx.create_gpu_image_view(&game.render_state.shadow_depth_image, {.DEPTH}, .D2_ARRAY)

	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.shadow_depth_image.image_view)
	gfx.defer_destroy(
		&gfx.renderer().global_arena,
		game.render_state.shadow_depth_image.image,
		game.render_state.shadow_depth_image.allocation,
	)

	depth_image := &game.render_state.shadow_depth_image

	for &view, i in game.render_state.shadow_depth_attach_image_views {
		view = gfx.create_image_view(depth_image.image, depth_image.format, {.DEPTH}, .D2, 0, 1, i, 1)
		gfx.defer_destroy(&gfx.renderer().global_arena, view)
	}
}

init_test_resources :: proc() {
	tony_mc_mapface := gfx.load_image_from_memory(asset_content(.t_tony_mc_mapface), .D3, .D3)

	dfg := gfx.load_image_from_memory(asset_content(.t_dfg))

	env := gfx.load_image_from_memory(asset_content(.t_test_cubemap_ld), .D2, .CUBE)

	// Default Imageture Sampler
	default_sampler := gfx.create_sampler(.LINEAR, .REPEAT, max_lod = 10.0, max_anisotropy = gfx.renderer().limits.maxSamplerAnisotropy)
	gfx.defer_destroy(&gfx.renderer().global_arena, default_sampler)

	font_image_sampler := gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE)
	gfx.defer_destroy(&gfx.renderer().global_arena, font_image_sampler)

	// Shadow Depth Imageture Sampler
	shadow_depth_sampler := gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE, .LESS_OR_EQUAL)
	gfx.defer_destroy(&gfx.renderer().global_arena, shadow_depth_sampler)

	env_sampler := gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE, max_lod = 8.0)
	gfx.defer_destroy(&gfx.renderer().global_arena, env_sampler)

	{
		rs := &game.render_state
		tr := &rs.temp_resources

		rs.shadow_depth_image_id = gfx.add_image(game.render_state.shadow_depth_image)
		tr.tony_mc_mapface_id = gfx.add_image(tony_mc_mapface)
		tr.dfg_id = gfx.add_image(dfg)
		tr.env_id = gfx.add_image(env)

		tr.default_sampler_id = gfx.add_sampler(default_sampler)
		tr.shadow_depth_sampler_id = gfx.add_sampler(shadow_depth_sampler)
		tr.env_sampler_id = gfx.add_sampler(env_sampler)

		tr.resolved_image_id = gfx.add_image(gfx.renderer().resolve_image)
	}
}

init_test_materials :: proc() {
	game.render_state.scene_resources.materials_buffer = gfx.create_buffer(
		GPUMaterial,
		20,
		{.TRANSFER_DST, .STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		.GPU_ONLY,
	)
	gfx.defer_destroy_buffer(&gfx.renderer().global_arena, game.render_state.scene_resources.materials_buffer)

	base_color_id := gfx.add_image(gfx.load_image_from_memory(asset_content(.t_test_basecolor2)))
	normal_map_id := gfx.add_image(gfx.load_image_from_memory(asset_content(.t_test_normalmap)))
	proughness_metallic_ao_id := gfx.add_image(gfx.load_image_from_memory(asset_content(.t_test_rma)))

	add_material({base_color_id = base_color_id, normal_map_id = normal_map_id, ao_roughness_metallic_id = proughness_metallic_ao_id})
	add_material({base_color_id = base_color_id, normal_map_id = normal_map_id, ao_roughness_metallic_id = proughness_metallic_ao_id})

	base_color_id = gfx.add_image(gfx.load_image_from_memory(asset_content(.t_basecolor)))
	normal_map_id = gfx.add_image(gfx.load_image_from_memory(asset_content(.t_normalmap)))
	proughness_metallic_ao_id = gfx.add_image(gfx.load_image_from_memory(asset_content(.t_rma)))

	add_material({base_color_id = base_color_id, normal_map_id = normal_map_id, ao_roughness_metallic_id = proughness_metallic_ao_id})
}

init_pipelines :: proc() {
	assert(sp.createGlobalSession(sp.API_VERSION, &game.render_state.global_session) == sp.OK)

	init_mesh_pipelines()
	init_skinning_pipelines()
	init_skybox_pipelines()
	init_tonemapper_pipelines()
	init_ui_pipelines()
}

init_mesh_pipelines :: proc() {
	game.render_state.mesh_pipeline = add_graphics_shader("shaders/mesh.slang", proc(module: vk.ShaderModule) -> gfx.GraphicsPipeline {
		return gfx.create_graphics_pipeline(
			name = "Basic_Mesh_Pipeline",
			shader = module,
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = {.BACK},
			front_face = .COUNTER_CLOCKWISE,
			depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
			color_format = gfx.renderer().draw_image.format,
			multisampling_samples = gfx.msaa_samples(),
			push_constant = GPUDrawPushConstants,
		)
	})

	game.render_state.mesh_shadow_pipeline = add_graphics_shader(
	"shaders/shadow_depth.slang",
	proc(module: vk.ShaderModule) -> gfx.GraphicsPipeline {
		return gfx.create_graphics_pipeline(
			name = "Shadow_Depth_Pipeline",
			shader = module,
			vertex_entry = "vertex_main",
			fragment_entry = nil, // TODO: Only need vertex depth currently for shadow maps.
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = {},
			front_face = .COUNTER_CLOCKWISE,
			depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
			push_constant = GPUDrawPushConstants,
		)
	},
	)
}

init_skinning_pipelines :: proc() {
	game.render_state.skinning_pipeline = add_compute_shader(
		"shaders/skinning.slang",
		proc(module: vk.ShaderModule) -> gfx.ComputePipeline {
			return gfx.create_compute_pipelines("Skinning", module, GPUSkinningPushConstants)
		},
	)
}

init_skybox_pipelines :: proc() {
	game.render_state.skybox_pipeline = add_graphics_shader("shaders/skybox.slang", proc(module: vk.ShaderModule) -> gfx.GraphicsPipeline {
		return gfx.create_graphics_pipeline(
			name = "Skybox_Pipeline",
			shader = module,
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = {.BACK},
			front_face = .COUNTER_CLOCKWISE,
			depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
			color_format = gfx.renderer().draw_image.format,
			multisampling_samples = gfx.msaa_samples(),
			push_constant = GPUSkyboxPushConstants,
		)
	})
}

init_tonemapper_pipelines :: proc() {
	game.render_state.tonemapper_pipeline = add_compute_shader(
		"shaders/tonemapping.slang",
		proc(module: vk.ShaderModule) -> gfx.ComputePipeline {
			return gfx.create_compute_pipelines("Tonemapper_Pipeline", module, GPUPostProcessingPushConstants)
		},
	)
}

init_ui_pipelines :: proc() {
	game.render_state.ui_pass = create_ui_pass()
	game.render_state.ui_pass.render_pass->init()
}

// GPUFontRendererPushConstants :: struct {
// 	atlas:     ImageId,
// 	sampler:   u32,
// 	instances: GPUPtr(GPU_Font_Instance),
// }

init_font_renderer :: proc() {
	// font_state := &game.render_state.font_state
	//
	// fontstash.Init(&font_state.font_ctx, 512, 512, .BOTTOMLEFT)
	// font_state.font_index = fontstash.AddFontMem(&font_state.font_ctx, "Default", asset_content(.f_roboto_regular), false)
	//
	// font_state.font_pip_layout = gfx.create_pipeline_layout_pc(
	// 	"Font_Pipeline_Layout",
	// 	&game.render_state.bindless_system.descriptor_layout,
	// 	GPUFontRendererPushConstants,
	// )
	// gfx.defer_destroy(&gfx.renderer().global_arena, font_state.font_pip_layout)
	//
	// game.render_state.font_state.font_shader = add_shader("shaders/text.slang", proc(module: vk.ShaderModule, _: rawptr) -> (vk.Pipeline, bool) {
	// 	return gfx.create_graphics_pipeline(
	// 		name = "Font_Pipeline_Layout",
	// 		pipeline_layout = game.render_state.font_state.font_pip_layout,
	// 		shader = module,
	// 		input_topology = .TRIANGLE_LIST,
	// 		polygon_mode = .FILL,
	// 		cull_mode = {},
	// 		front_face = .COUNTER_CLOCKWISE,
	// 		blend_mode = .Alpha,
	// 		depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
	// 		color_format = gfx.renderer().draw_image.format,
	// 		multisampling_samples = gfx.msaa_samples(),
	// 	)
	// })

	// font_state.font_instance_buf = gfx.create_buffer(
	// 	GPU_Font_Instance,
	//        512,
	// 	{.TRANSFER_DST, .STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
	// 	.CPU_TO_GPU,
	// )
	//
	// font_state.font_index_buf = gfx.create_buffer(u32, 6, {.INDEX_BUFFER, .TRANSFER_DST}, .GPU_ONLY)
	// gfx.staging_write_buffer_slice(&font_state.font_index_buf, []u32{2, 1, 0, 1, 2, 3})
}

init_buffers :: proc() {
	// Skybox
	{
		mesh, ok := load_gpu_mesh_from_file(asset_path(.sm_skybox))
		assert(ok)
		defer_destroy_gpu_mesh(&gfx.renderer().global_arena, mesh)
		game.render_state.skybox_mesh = mesh
	}

	for &frame in game.render_state.frame_data {
		// Global uniform buffer
		frame.global_uniform_buffer = gfx.create_buffer(GPUGlobalData, 1, {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS}, .CPU_TO_GPU)
		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, frame.global_uniform_buffer)

		// Model matrices
		frame.model_matrices_buffer = gfx.create_buffer(Mat4x4, 16_384, {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS}, .CPU_TO_GPU)
		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, frame.model_matrices_buffer)

		frame.cascade_matrices_buffer = gfx.create_buffer(Mat4x4, NUM_CASCADES, {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS}, .CPU_TO_GPU)
		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, frame.cascade_matrices_buffer)

		frame.cascade_configs_buffer = gfx.create_buffer(
			GPUCascadeConfig,
			NUM_CASCADES,
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)
		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, frame.cascade_configs_buffer)
	}

	// comp_coeffs := process_sh_coefficients_from_cubemap_file(asset_path(.t_test_cubemap_ld))
	// comp_coeffs := process_sh_coefficients_from_equirectangular_file("assets/gen/test_equirectangular.ktx2")

	environment := &game.render_state.global_uniform_data.environment

	// TODO: TEMP: Remove this at some point. Just testing volumes!
	ir_volume := new_entity(Irradiance_Volume)
	init_irradiance_volume(ir_volume)

	game.render_state.scene_resources.point_light_buffer = gfx.create_buffer(
		GPUPointLight,
		len(game.render_state.scene_resources.point_lights),
		{.TRANSFER_DST, .SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
		.GPU_ONLY,
	)
	gfx.defer_destroy_buffer(&gfx.renderer().global_arena, game.render_state.scene_resources.point_light_buffer)

	environment^ = {
		world_to_volume  = linalg.matrix4_from_trs_f32(ir_volume.translation, ir_volume.rotation, ir_volume.sh_volume_scale),
		sh_volume        = ir_volume.gpu_buffer.address,
		// sh_coeffs       = comp_coeffs,
		// sh_volume_size  = ir_volume.sh_volume_size,
		// sh_volume_scale = ir_volume.sh_volume_scale,
		point_lights     = game.render_state.scene_resources.point_light_buffer.address,
		num_point_lights = u32(len(game.render_state.scene_resources.point_lights)),
		env_sampler      = game.render_state.temp_resources.env_sampler_id,
		env_map          = game.render_state.temp_resources.env_id,
		dfg              = game.render_state.temp_resources.dfg_id,
	}

	reserve(&game.render_state.model_matrices, 16_000)
}

draw :: proc() {
	scope_stat_time(.Render)

	when ODIN_DEBUG {
		if check_shader_hotreload() {
			gfx.vk_check(vk.DeviceWaitIdle(gfx.renderer().device))
			hotreload_start := time.now()
			if hotreload_modified_shaders() {
				log.info("Shaders hotreloaded in", time.since(hotreload_start))
			} else {
				log.warn("Shaders failed to load!")
			}
		}
	}

	// TEMP: test draw command
	for &ball in get_entities(Ball) {
		draw_skeletal_mesh(&ball.skel_mesh_instance, ball.material, ball.translation, ball.rotation, 1)
	}

	for static_mesh in get_entities(StaticMesh) {
		draw_mesh(static_mesh.mesh, static_mesh.material, static_mesh.translation, static_mesh.rotation, 1)
	}

	// {
	// 	font_state := &game.render_state.font_state
	//
	// 	if len(font_state.font_instances) > 0 {
	// 		gfx.write_buffer_slice(&font_state.font_instance_buf, font_state.font_instances[:])
	// 	}
	//
	// 	atlas_size := UVec2{u32(font_state.font_ctx.width), u32(font_state.font_ctx.height)}
	// 	dirty_texture :=
	// 		font_state.font_ctx.dirtyRect[0] < font_state.font_ctx.dirtyRect[2] &&
	// 		font_state.font_ctx.dirtyRect[1] < font_state.font_ctx.dirtyRect[3]
	//
	// 	if font_state.font_atlas_size != atlas_size {
	// 		dirty_texture = true
	// 		font_state.font_atlas_size = atlas_size
	//
	// 		vk.DeviceWaitIdle(gfx.renderer().device)
	//
	// 		if font_state.font_img.image != 0 {
	// 			gfx.defer_destroy_gpu_image(&gfx.current_frame().arena, font_state.font_img)
	// 		}
	//
	// 		font_state.font_img = gfx.create_gpu_image(
	// 			.R8_UINT,
	// 			{atlas_size.x, atlas_size.y, 1},
	// 			{.TRANSFER_DST, .SAMPLED},
	// 		)
	// 		gfx.create_gpu_image_view(&font_state.font_img, {.COLOR})
	//
	// 		set_texture(font_state.font_img, FONT_ATLAS_ID)
	// 	}
	//
	// 	if dirty_texture {
	// 		gfx.staging_write_image_slice(&font_state.font_img, font_state.font_ctx.textureData)
	// 	}
	//
	// 	font_state.font_ctx.state_count = 0
	// 	fontstash.Reset(&font_state.font_ctx)
	// }

	cmd := gfx.begin_command_buffer()

	update_buffers()

	// Begin Skinning pass
	for instance in current_frame_game().skel_instances {
		gfx.transition_buffer(
			cmd,
			instance.preskinned_vertex_buffers[gfx.current_frame_index()],
			{.MEMORY_READ},
			{.MEMORY_WRITE},
			gfx.renderer().graphics_queue_family,
		)
		skinning_pass(cmd, instance)
		gfx.transition_buffer(
			cmd,
			instance.preskinned_vertex_buffers[gfx.current_frame_index()],
			{.MEMORY_WRITE},
			{.MEMORY_READ},
			gfx.renderer().graphics_queue_family,
		)
	}
	// End skinning pass

	// Begin shadow pass
	gfx.transition_image(cmd, &game.render_state.shadow_depth_image, .DEPTH_ATTACHMENT_OPTIMAL)
	for i in 0 ..< len(game.render_state.shadow_depth_attach_image_views) {
		shadow_map_pass(cmd, u32(i))
	}
	// End shadow pass

	// Begin mesh pass
	gfx.transition_image(cmd, &gfx.renderer().draw_image, .COLOR_ATTACHMENT_OPTIMAL)
	gfx.transition_image(cmd, &gfx.renderer().depth_image, .DEPTH_ATTACHMENT_OPTIMAL)
	gfx.transition_image(cmd, &game.render_state.shadow_depth_image, .DEPTH_READ_ONLY_OPTIMAL)
	if game.render_state.draw_skybox {
		skybox_pass(cmd)
	}
	geometry_pass(cmd)
	// End mesh pass

	// {
	// 	font_state := &game.render_state.font_state
	//
	// 	// Draw text
	// 	if len(font_state.font_instances) > 0 {
	// 		color_attachment := gfx.init_attachment_info(gfx.renderer().draw_image.image_view, nil, .GENERAL)
	// 		depth_attachment := gfx.init_attachment_info(
	// 			gfx.renderer().depth_image.image_view,
	// 			&{depthStencil = {depth = 1.0}},
	// 			.DEPTH_ATTACHMENT_OPTIMAL,
	// 		)
	//
	// 		render_info := gfx.init_rendering_info(gfx.renderer().draw_extent, &color_attachment, &depth_attachment)
	// 		vk.CmdBeginRendering(cmd, &render_info)
	// 		gfx.set_viewport_and_scissor(cmd, gfx.renderer().draw_extent)
	//
	// 		gfx.cmd_bind_pipeline(cmd, .GRAPHICS, get_shader(font_state.font_shader).pipeline)
	//
	// 		vk.CmdBindIndexBuffer(cmd, font_state.font_index_buf.buffer, 0, .UINT32)
	//
	// 		gfx.cmd_push_constants(
	// 			cmd,
	// 			font_state.font_pip_layout,
	// 			{.VERTEX, .FRAGMENT},
	// 			0,
	// 			size_of(GPUFontRendererPushConstants),
	// 			&GPUFontRendererPushConstants {
	// 				atlas = FONT_ATLAS_ID,
	// 				sampler = DEFAULT_SAMPLER_ID,
	// 				instances = font_state.font_instance_buf.address,
	// 			},
	// 		)
	//
	// 		vk.CmdDrawIndexed(cmd, 6, u32(len(font_state.font_instances)), 0, 0, 0)
	// 		clear(&font_state.font_instances)
	//
	// 		gfx.cmd_end_rendering(cmd)
	// 	}
	// }

	final_image: vk.Image
	switch game.view_state {
	case .SceneDepth:
		gfx.transition_image(cmd, &gfx.renderer().depth_image, .TRANSFER_SRC_OPTIMAL)
		final_image = gfx.renderer().depth_image.image
	case .ShadowDepth:
		gfx.transition_image(cmd, &game.render_state.shadow_depth_image, .TRANSFER_SRC_OPTIMAL)
		final_image = game.render_state.shadow_depth_image.image
	case .SceneColor:
		if gfx.msaa_enabled() {
			// Resolve MSAA
			gfx.transition_image(cmd, &gfx.renderer().draw_image, .TRANSFER_SRC_OPTIMAL)
			gfx.transition_image(cmd, &gfx.renderer().resolve_image, .TRANSFER_DST_OPTIMAL)

			ex := gfx.renderer().draw_extent

			resolve_region := vk.ImageResolve {
				srcSubresource = {mipLevel = 0, aspectMask = {.COLOR}, baseArrayLayer = 0, layerCount = 1},
				srcOffset = {0, 0, 0},
				dstSubresource = {mipLevel = 0, aspectMask = {.COLOR}, baseArrayLayer = 0, layerCount = 1},
				dstOffset = {0, 0, 0},
				extent = {ex.width, ex.height, 1},
			}

			vk.CmdResolveImage(
				cmd,
				// gfx.renderer().draw_image.image,
				gfx.renderer().draw_image.image,
				.TRANSFER_SRC_OPTIMAL,
				gfx.renderer().resolve_image.image,
				.TRANSFER_DST_OPTIMAL,
				1,
				&resolve_region,
			)

			gfx.transition_image(cmd, &gfx.renderer().resolve_image, .GENERAL)
			post_processing_pass(cmd)
			ui_pass(cmd)

			// Prepare swapchain image
			gfx.transition_image(cmd, &gfx.renderer().resolve_image, .TRANSFER_SRC_OPTIMAL)
			final_image = gfx.renderer().resolve_image.image
		} else {
			post_processing_pass(cmd)
			// Prepare swapchain image
			gfx.transition_image(cmd, &gfx.renderer().draw_image, .TRANSFER_SRC_OPTIMAL)
			final_image = gfx.renderer().draw_image.image
		}
	}

	gfx.copy_image_to_swapchain(cmd, final_image, gfx.renderer().draw_extent)

	swapchain_resized := gfx.submit(cmd)

	if swapchain_resized {
		gfx.write_descriptor_set(
			gfx.r_ctx.bindless_system.descriptor_set,
			{
				{
					binding = gfx.BINDLESS_STORAGE_IMAGES,
					type = .STORAGE_IMAGE,
					image_view = gfx.renderer().resolve_image.image_view,
					image_layout = .GENERAL,
					array_index = u32(game.render_state.temp_resources.resolved_image_id),
				},
			},
		)
	}

	clear(&current_frame_game().mesh_draws)
	clear(&current_frame_game().skel_instances)
	clear(&game.render_state.model_matrices)
}

skinning_pass :: proc(cmd: vk.CommandBuffer, instance: ^SkeletalMeshInstance) {
	gfx.cmd_bind_pipeline(cmd, game.render_state.skinning_pipeline)

	gfx.cmd_push_constants(
		cmd,
		GPUSkinningPushConstants {
			input_vertex_buffer = instance.skel.buffers.vertex_buffer.address,
			output_vertex_buffer = instance.preskinned_vertex_buffers[gfx.current_frame_index()].address,
			attrs = instance.skel.buffers.skel_vert_attrs_buffer.address,
			joint_matrices = instance.joint_matrices_buffers[gfx.current_frame_index()].address,
			vertex_count = instance.skel.buffers.vertex_count,
		},
	)

	gfx.cmd_dispatch(cmd, u32(math.ceil(f32(instance.skel.buffers.vertex_count) / 64.0)))
}

// TODO: Encode this as indirect draw args instead.
MeshDraw :: struct {
	vertex_buffer_address: GPUPtr(Vertex),
	index_buffer:          vk.Buffer,
	index_count:           u32,
	model_index:           u32,
	material_index:        MaterialId,
}

draw_mesh :: proc(mesh: GPUMeshBuffers, material: MaterialId, translation: Vec3, rotation: quaternion128, scale: [3]f32) {
	model_index := len(game.render_state.model_matrices)

	append(
		&current_frame_game().mesh_draws,
		MeshDraw {
			vertex_buffer_address = mesh.vertex_buffer.address,
			index_buffer = mesh.index_buffer.buffer,
			index_count = mesh.index_count,
			model_index = u32(model_index),
			material_index = material,
		},
	)

	append(&game.render_state.model_matrices, linalg.matrix4_from_trs_f32(translation, rotation, scale))
}

draw_skeletal_mesh :: proc(
	instance: ^SkeletalMeshInstance,
	material: MaterialId,
	translation: Vec3,
	rotation: quaternion128,
	scale: Vec3,
) {
	model_index := len(game.render_state.model_matrices)

	append(&current_frame_game().skel_instances, instance)
	append(
		&current_frame_game().mesh_draws,
		MeshDraw {
			vertex_buffer_address = instance.preskinned_vertex_buffers[gfx.current_frame_index()].address,
			index_buffer = instance.skel.buffers.index_buffer.buffer,
			index_count = instance.skel.buffers.index_count,
			model_index = u32(model_index),
			material_index = material,
		},
	)

	append(&game.render_state.model_matrices, linalg.matrix4_from_trs_f32(translation, rotation, scale))
}

shadow_map_pass :: proc(cmd: vk.CommandBuffer, cascade: u32) {
	image_view := game.render_state.shadow_depth_attach_image_views[cascade]
    extent := game.render_state.shadow_depth_image.extent;

    width := extent.width
	height := extent.height

	gfx.cmd_begin_rendering(cmd,
		area = {width, height},
		depth_attachment = &{
            view = image_view,
            layout = .DEPTH_ATTACHMENT_OPTIMAL,
            clear_value = &{
                depthStencil = {depth = 1.0}
            }, 
        },
	)
	gfx.set_viewport_and_scissor(cmd, game.render_state.shadow_depth_image.extent)

	gfx.cmd_bind_pipeline(cmd, game.render_state.mesh_shadow_pipeline)

	for mesh_draw in current_frame_game().mesh_draws {
		gfx.cmd_bind_index_buffer(cmd, mesh_draw.index_buffer)

		gfx.cmd_push_constants(cmd,
			GPUDrawShadowDepthPushConstants {
				vertex_buffer = mesh_draw.vertex_buffer_address,
				model_matrices = current_frame_game().model_matrices_buffer.address,
				global_data = current_frame_game().global_uniform_buffer.address,
				model_index = mesh_draw.model_index,
				cascade_index = cascade,
			},
		)

		gfx.cmd_draw_indexed(cmd, mesh_draw.index_count)
	}

	gfx.cmd_end_rendering(cmd)
}

geometry_pass :: proc(cmd: vk.CommandBuffer) {
	gfx.cmd_begin_rendering(cmd, 
        area = gfx.r_ctx.draw_extent,
        color_attachment = &{
            view = gfx.r_ctx.draw_image.image_view,
            layout = .GENERAL,
        },
        depth_attachment = &{
            view = gfx.r_ctx.depth_image.image_view,
            clear_value = &{depthStencil = {depth = 1.0 }},
            layout = .DEPTH_ATTACHMENT_OPTIMAL,
        }
    )
	gfx.set_viewport_and_scissor(cmd, gfx.renderer().draw_extent)

	gfx.cmd_bind_pipeline(cmd, game.render_state.mesh_pipeline)

	for mesh_draw in current_frame_game().mesh_draws {
		gfx.cmd_bind_index_buffer(cmd, mesh_draw.index_buffer)
		gfx.cmd_push_constants(
			cmd,
			GPUDrawPushConstants {
				global_data_buffer = current_frame_game().global_uniform_buffer.address,
				vertex_buffer = mesh_draw.vertex_buffer_address,
				model_matrices = current_frame_game().model_matrices_buffer.address,
				materials = game.render_state.scene_resources.materials_buffer.address,
				model_index = mesh_draw.model_index,
				material_index = mesh_draw.material_index,
				num_cascades = NUM_CASCADES,
				shadow_depth = game.render_state.shadow_depth_image_id,
				shadow_sampler = game.render_state.temp_resources.shadow_depth_sampler_id,
			},
		)

		gfx.cmd_draw_indexed(cmd, mesh_draw.index_count)
	}

	gfx.cmd_end_rendering(cmd)
}

skybox_pass :: proc(cmd: vk.CommandBuffer) {
    gfx.cmd_begin_rendering(cmd,
        area = gfx.r_ctx.draw_extent,
        color_attachment = &{
            view  = gfx.r_ctx.draw_image.image_view, 
            layout = .COLOR_ATTACHMENT_OPTIMAL,
        },
        depth_attachment = &{
            view = gfx.r_ctx.depth_image.image_view,
            clear_value = &{depthStencil = {depth = 1.0}},
            layout = .DEPTH_ATTACHMENT_OPTIMAL,
        }
    )
	gfx.set_viewport_and_scissor(cmd, gfx.renderer().draw_extent)

	gfx.cmd_bind_pipeline(cmd, game.render_state.skybox_pipeline)
	gfx.cmd_bind_index_buffer(cmd, game.render_state.skybox_mesh.index_buffer.buffer)
	gfx.cmd_push_constants(
		cmd,
		GPUSkyboxPushConstants {
			vertex_buffer = game.render_state.skybox_mesh.vertex_buffer.address,
			global_data_buffer = current_frame_game().global_uniform_buffer.address,
		},
	)

	gfx.cmd_draw_indexed(cmd, game.render_state.skybox_mesh.index_count)
	gfx.cmd_end_rendering(cmd)
}

post_processing_pass :: proc(cmd: vk.CommandBuffer) {
	gfx.cmd_bind_pipeline(cmd, game.render_state.tonemapper_pipeline)
	gfx.cmd_push_constants(
		cmd,
		GPUPostProcessingPushConstants {
			resolved_image = game.render_state.temp_resources.resolved_image_id,
			tony_mc_mapface = game.render_state.temp_resources.tony_mc_mapface_id,
			sampler = game.render_state.temp_resources.default_sampler_id,
		},
	)

	vk.CmdDispatch(
		cmd,
		u32(math.ceil(f32(gfx.renderer().draw_extent.width) / 16.0)),
		u32(math.ceil(f32(gfx.renderer().draw_extent.height) / 16.0)),
		1,
	)
}

ui_pass :: proc(cmd: vk.CommandBuffer) {
	game.render_state.ui_pass.render_pass->run(cmd)
	// gfx.cmd_bind_pipeline(cmd, game.render_state.ui_pipeline)
	//
	// vk.CmdDispatch(
	// 	cmd,
	// 	u32(math.ceil(f32(gfx.renderer().draw_extent.width) / 16.0)),
	// 	u32(math.ceil(f32(gfx.renderer().draw_extent.height) / 16.0)),
	// 	1,
	// )
}

calculate_shadow_view_projection_matrices :: proc(near: f32 = 0.1, far: f32 = 300) {
	cascade_split_lambda := game.config.shadow_cascade_split_lambda

	cascade_splits: [NUM_CASCADES]f32

	clip_range := far - near
	ratio := far / near

	// Calculate split depths based on view camera frustum
	// Based on method presented in https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch10.html
	for i in 0 ..< NUM_CASCADES {
		p := (f32(i) + 1) / f32(NUM_CASCADES)
		log := near * math.pow(ratio, p)
		uniform := near + clip_range * p
		d := cascade_split_lambda * (log - uniform) + uniform
		cascade_splits[i] = (d - near) / clip_range
	}

	last_near := near
	for i in 0 ..< NUM_CASCADES {
		split_dist := cascade_splits[i]

		test_far := near + split_dist * clip_range

		world_to_clip := get_current_projection_matrix_clipped(near = last_near, far = test_far) * get_current_view_matrix()
		clip_to_world := linalg.inverse(world_to_clip)

		CORNERS_NDC :: [8]Vec4 {
			{-1.0, -1.0, -1.0, 1.0},
			{-1.0, -1.0, 1.0, 1.0},
			{-1.0, 1.0, -1.0, 1.0},
			{-1.0, 1.0, 1.0, 1.0},
			{1.0, -1.0, -1.0, 1.0},
			{1.0, -1.0, 1.0, 1.0},
			{1.0, 1.0, -1.0, 1.0},
			{1.0, 1.0, 1.0, 1.0},
		}

		corners_ws: [8]Vec4
		for pos_fs, j in CORNERS_NDC {
			pos_ws := clip_to_world * pos_fs
			corners_ws[j] = pos_ws / pos_ws.w

			if i == 1 {
				debug_draw_dot(corners_ws[j].xyz)
			}
		}

		center_ws: Vec3
		for corner_ws in corners_ws {
			center_ws += corner_ws.xyz
		}
		center_ws /= len(corners_ws)

		sun_dir := game.state.environment.sun_direction

		radius: f32
		for corner in corners_ws {
			// distance := linalg.length(corner - center_ws)
			// radius = max(radius, distance)

			distance_x := math.abs(corner.x - center_ws.x)
			distance_y := math.abs(corner.y - center_ws.y)
			distance_z := math.abs(corner.z - center_ws.z)
			radius = max(radius, distance_x, distance_y, distance_z)
		}

		aabb: Aabb
		aabb.min = -radius
		aabb.max = radius

		cascade_world_to_view := linalg.matrix4_look_at_f32(center_ws, center_ws + sun_dir, {0.0, 1.0, 0.0})
		cascade_view_to_clip := gfx.matrix_ortho3d_z0_f32(aabb.min.x, aabb.max.x, aabb.min.y, aabb.max.y, aabb.max.z * 10, aabb.min.z)
		cascade_view_to_clip[1][1] *= -1.0

		if game.config.use_stable_shadow_maps {
			sMapSize := f32(game.config.shadow_map_size)

			shadowMatrix := cascade_view_to_clip * cascade_world_to_view
			shadowOrigin := Vec4{0, 0, 0, 1}
			shadowOrigin = shadowMatrix * shadowOrigin
			shadowOrigin *= sMapSize / 2.0

			roundedOrigin := linalg.round(shadowOrigin)
			roundOffset := roundedOrigin - shadowOrigin
			roundOffset *= 2.0 / sMapSize
			roundOffset.zw = 0.0

			shadowProj := cascade_view_to_clip
			shadowProj[3] += roundOffset
			cascade_view_to_clip = shadowProj
		}

		game.render_state.cascade_world_to_shadows[i] = cascade_view_to_clip * cascade_world_to_view
		game.render_state.cascade_configs[i] = {
			split_dist = test_far,
			bias       = game.config.shadow_map_biases[i],
			slope_bias = game.config.shadow_map_slope_biases[i],
		}

		last_near = test_far
	}
}

update_buffers :: proc() {
	global_uniform_data := &game.render_state.global_uniform_data
	player := get_entity(game.state.player_id)

	global_uniform_data.view_to_clip = get_current_projection_matrix()
	global_uniform_data.world_to_view = get_current_view_matrix()

	global_uniform_data.sun_color = game.state.environment.sun_color
	global_uniform_data.sky_color = game.state.environment.sky_color

	global_uniform_data.camera_pos = player != nil ? player.translation : {0, 0, 0}
	global_uniform_data.sun_direction = game.state.environment.sun_direction

	global_uniform_data.environment.num_point_lights = auto_cast len_entities(PointLight)

	global_uniform_data.cascade_world_to_shadows = current_frame_game().cascade_matrices_buffer.address
	global_uniform_data.cascade_configs = current_frame_game().cascade_configs_buffer.address
	global_uniform_data.default_sampler = game.render_state.temp_resources.default_sampler_id

	gfx.write_buffer_slice(&current_frame_game().cascade_matrices_buffer, game.render_state.cascade_world_to_shadows[:])
	gfx.write_buffer_slice(&current_frame_game().cascade_configs_buffer, game.render_state.cascade_configs[:])
	gfx.write_buffer(&current_frame_game().global_uniform_buffer, global_uniform_data)

	gfx.write_buffer_slice(&current_frame_game().model_matrices_buffer, game.render_state.model_matrices[:])

	for &ball in get_entities(Ball) {
		gfx.write_buffer_slice(
			&ball.skel_mesh_instance.joint_matrices_buffers[gfx.current_frame_index()],
			ball.skel_animator.calc_joints[:],
		)
	}

	for &point_light, i in get_entities(PointLight) {
		if i >= len(game.render_state.scene_resources.point_lights) do break
		game.render_state.scene_resources.point_lights[i] = point_light_to_gpu(point_light)
	}

	gfx.staging_write_buffer_slice(
		&game.render_state.scene_resources.point_light_buffer,
		game.render_state.scene_resources.point_lights[:],
	)

	calculate_shadow_view_projection_matrices()
}

renderer_shutdown :: proc() {
	// destroy_shaders()
}
