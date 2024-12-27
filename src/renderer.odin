package game

import sm "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:os/os2"
import "core:time"

import "vendor:fontstash"
import "vendor:glfw"
import vk "vendor:vulkan"

import sp "deps:odin-slang/slang"
import vma "deps:odin-vma"

import gfx "gfx"

SHADOW_ID: TextureId : 0
TONY_MC_MAPFACE_ID: TextureId : 1
DFG_ID: TextureId : 2
ENVIRONMENT_MAP_ID: TextureId : 3
TEST_SH_0_3_3D_ID: TextureId : 4
TEST_SH_4_7_3D_ID: TextureId : 5
TEST_SH_8_9_3D_ID: TextureId : 6
FONT_ATLAS_ID: TextureId : 7

DEFAULT_SAMPLER_ID: u32 : 0
SHADOW_SAMPLER_ID: u32 : 1
ENVIRONMENT_SAMPLER_ID: u32 : 2
FONT_SAMPLER_ID: u32 : 3

RESOLVED_IMAGE_ID: u32 : 0

MAX_BINDLESS_IMAGES :: 100
RESERVED_BINDLESS_IMAGES_COUNT :: 10
MAX_BINDLESS_SAMPLERS :: 32

NUM_CASCADES: u32 : 3

@(ShaderShared)
GPUDrawPushConstants :: struct {
	global_data_buffer: vk.DeviceAddress, // ^GPUGlobalDataBuffer
	vertex_buffer:      vk.DeviceAddress, // []Vertex
	model_matrices:     vk.DeviceAddress, // []Mat4x4
	materials:          vk.DeviceAddress, // []GPUMaterial
	model_index:        u32,
	material_index:     MaterialId,
	num_cascades:       u32,
}

@(ShaderShared)
GPUDrawShadowDepthPushConstants :: struct {
	vertex_buffer:  vk.DeviceAddress, // []Vertex
	model_matrices: vk.DeviceAddress, // []Mat4x4
	global_data:    vk.DeviceAddress, // []Mat4x4
	model_index:    u32,
	cascade_index:  u32,
}

@(ShaderShared)
GPUSkinningPushConstants :: struct {
	input_vertex_buffer:  vk.DeviceAddress,
	output_vertex_buffer: vk.DeviceAddress,
	joint_matrices:       vk.DeviceAddress,
	attrs:                vk.DeviceAddress,
	vertex_count:         u32,
}

@(ShaderShared)
GPUSkyboxPushConstants :: struct {
	vertex_buffer:      vk.DeviceAddress,
	global_data_buffer: vk.DeviceAddress,
}

// TODO: Make this into proper assets?
TextureId :: u32
MaterialId :: u32
ShaderId :: u32

@(ShaderShared)
GPUMaterial :: struct {
	base_color_id:            TextureId,
	normal_map_id:            TextureId,
	ao_roughness_metallic_id: TextureId,
}

@(ShaderShared)
GPUEnvironment :: struct {
	sh_volume:        vk.DeviceAddress, // []Sh_Coefficients
	point_lights:     vk.DeviceAddress, // []GPU_Point_Light
	num_point_lights: u32,
}

@(ShaderShared)
GPUCascadeConfig :: struct {
	split_dist: f32,
	bias:       f32,
	slope_bias: f32,
}

@(ShaderShared)
GPUGlobalData :: struct #max_field_align (16) {
	cascade_world_to_shadows: vk.DeviceAddress,
	cascade_configs:          vk.DeviceAddress,
	projection_matrix:        Mat4x4,
	view_matrix:              Mat4x4,
	sun_color:                Vec3,
	sky_color:                Vec3,
	camera_pos:               Vec3,
	sun_direction:            Vec3,
	environment:              GPUEnvironment,
}

RenderState :: struct {
	frame_data:                      [gfx.FRAME_OVERLAP]GameFrameData,

	// Bindless textures, etc
	bindless_descriptor_layout:      vk.DescriptorSetLayout,
	bindless_descriptor_set:         vk.DescriptorSet,
	global_uniform_data:             GPUGlobalData,
	scene_resources:                 struct {
		bindless_textures:            [dynamic]gfx.GPUImage,
		bindless_texture_start_index: u32, // 0-10 is for reserved internal textures
		materials:                    [dynamic]GPUMaterial,
		materials_buffer:             gfx.GPUBuffer,
		point_lights:                 [256]GPU_Point_Light,
		point_light_buffer:           gfx.GPUBuffer,
	},
	temp_resources:                  struct {
		tony_mc_mapface:      gfx.GPUImage,
		dfg:                  gfx.GPUImage,
		env:                  gfx.GPUImage,
		mesh_image_sampler:   vk.Sampler,
		font_image_sampler:   vk.Sampler,
		shadow_depth_sampler: vk.Sampler,
		env_sampler:          vk.Sampler,
	},
	font_state:                      struct {
		font_ctx:          fontstash.FontContext,
		font_index:        int,
		font_atlas_size:   [2]u32,
		font_instances:    [dynamic]GPU_Font_Instance,
		font_pip_layout:   vk.PipelineLayout,
		font_shader:       ShaderId,
		font_instance_buf: gfx.GPUBuffer,
		font_index_buf:    gfx.GPUBuffer,
		font_img:          gfx.GPUImage,
	},
	//
	shaders:                         [dynamic]Shader,
	global_session:                  ^sp.IGlobalSession,

	// Mesh pipelines
	mesh_pipeline_layout:            vk.PipelineLayout,
	mesh_shader:                     ShaderId,
	model_matrices:                  [dynamic]Mat4x4,

	// Skeletal mesh pipelines
	skinning_pipeline_layout:        vk.PipelineLayout,
	skinning_shader:                 ShaderId,

	// Shadow pipelines
	shadow_pipeline_layout:          vk.PipelineLayout,
	mesh_shadow_shader:              ShaderId,
	shadow_depth_image:              gfx.GPUImage,
	shadow_depth_attach_image_views: [NUM_CASCADES]vk.ImageView,
	cascade_world_to_shadows:        [NUM_CASCADES]Mat4x4,
	cascade_configs:                 [NUM_CASCADES]GPUCascadeConfig,

	// Tonemapper pipelines
	tonemapper_shader:               ShaderId,
	tonemapper_pipeline_layout:      vk.PipelineLayout,

	// Skybox pipelines
	skybox_pipeline_layout:          vk.PipelineLayout,
	skybox_shader:                   ShaderId,
	skybox_mesh:                     GPUMeshBuffers,
	draw_skybox:                     bool,
}

GameFrameData :: struct {
	global_uniform_buffer:         gfx.GPUBuffer,
	model_matrices_buffer:         gfx.GPUBuffer,
	cascade_matrices_buffer:       gfx.GPUBuffer,
	cascade_configs_buffer:        gfx.GPUBuffer,
	test_preskinned_vertex_buffer: gfx.GPUBuffer,
	mesh_draws:                    [dynamic]MeshDraw,
	skel_instances:                [dynamic]^SkeletalMeshInstance,
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

add_texture :: proc(image: gfx.GPUImage) -> TextureId {
	scene_resources := &game.render_state.scene_resources
	texture_id := TextureId(scene_resources.bindless_texture_start_index + u32(len(scene_resources.bindless_textures)))

	append(&scene_resources.bindless_textures, image)

	gfx.write_descriptor_set(
		game.render_state.bindless_descriptor_set,
		{
			{
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = image.image_view,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = u32(texture_id),
			},
		},
	)

	return texture_id
}

// Writes a texture to the bindless ID and updates the descriptor.
set_texture :: proc(image: gfx.GPUImage, texture_id: TextureId) -> (resized: bool) {
	scene_resources := &game.render_state.scene_resources

	// Ensure our texture id can fit
	if TextureId(len(scene_resources.bindless_textures)) <= texture_id {
		resize(&scene_resources.bindless_textures, texture_id + 1)
		resized = true
	}

	scene_resources.bindless_textures[texture_id] = image

	gfx.write_descriptor_set(
		game.render_state.bindless_descriptor_set,
		{
			{
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = image.image_view,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = u32(texture_id),
			},
		},
	)

	return
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
	init_bindless_descriptors()
	init_pipelines()
	init_font_renderer()
	init_buffers()
	init_test_materials()
}

init_test_materials :: proc() {
	game.render_state.scene_resources.bindless_texture_start_index = RESERVED_BINDLESS_IMAGES_COUNT
	game.render_state.scene_resources.materials_buffer = gfx.create_buffer(
		size_of(GPUMaterial) * 20,
		{.TRANSFER_DST, .STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		.GPU_ONLY,
	)
	gfx.defer_destroy_buffer(&gfx.renderer().global_arena, game.render_state.scene_resources.materials_buffer)

	base_color_id := add_texture(gfx.load_image_from_file("assets/textures/test_basecolor2.ktx2"))
	normal_map_id := add_texture(gfx.load_image_from_file("assets/textures/test_normalmap.ktx2"))
	proughness_metallic_ao_id := add_texture(gfx.load_image_from_file("assets/textures/test_rma.ktx2"))

	add_material({base_color_id = base_color_id, normal_map_id = normal_map_id, ao_roughness_metallic_id = proughness_metallic_ao_id})
	add_material({base_color_id = base_color_id, normal_map_id = normal_map_id, ao_roughness_metallic_id = proughness_metallic_ao_id})

	base_color_id = add_texture(gfx.load_image_from_file("assets/textures/materialball2/basecolor.ktx2"))
	normal_map_id = add_texture(gfx.load_image_from_file("assets/textures/materialball2/normalmap.ktx2"))
	proughness_metallic_ao_id = add_texture(gfx.load_image_from_file("assets/textures/materialball2/rma.ktx2"))

	add_material({base_color_id = base_color_id, normal_map_id = normal_map_id, ao_roughness_metallic_id = proughness_metallic_ao_id})
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

init_bindless_descriptors :: proc() {
	game.render_state.bindless_descriptor_layout = gfx.create_descriptor_set_layout(
		{
			{binding = 0, type = .SAMPLED_IMAGE, count = MAX_BINDLESS_IMAGES},
			{binding = 1, type = .SAMPLER, count = MAX_BINDLESS_SAMPLERS},
			{binding = 2, type = .STORAGE_IMAGE},
		},
		{.UPDATE_AFTER_BIND_POOL},
		{.VERTEX, .FRAGMENT, .COMPUTE},
	)
	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.bindless_descriptor_layout)

	game.render_state.bindless_descriptor_set = gfx.allocate_descriptor_set(
		&gfx.renderer().global_descriptor_allocator,
		gfx.renderer().device,
		game.render_state.bindless_descriptor_layout,
	)

	tony_mc_mapface := gfx.load_image_from_file("assets/textures/tonemapping/tony-mc-mapface.ktx2", .D3, .D3)

	dfg := gfx.load_image_from_file("assets/gen/dfg.ktx2")

	env := gfx.load_image_from_file("assets/gen/test_cubemap_ld.ktx2", .D2, .CUBE)

	// Default Texture Sampler
	TEMP_mesh_image_sampler := gfx.create_sampler(
		.LINEAR,
		.REPEAT,
		max_lod = 10.0,
		max_anisotropy = gfx.renderer().limits.maxSamplerAnisotropy,
	)
	gfx.defer_destroy(&gfx.renderer().global_arena, TEMP_mesh_image_sampler)

	font_image_sampler := gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE)
	gfx.defer_destroy(&gfx.renderer().global_arena, font_image_sampler)

	// Shadow Depth Texture Sampler
	shadow_depth_sampler := gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE, .LESS_OR_EQUAL)
	gfx.defer_destroy(&gfx.renderer().global_arena, shadow_depth_sampler)

	env_sampler := gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE, max_lod = 8.0)
	gfx.defer_destroy(&gfx.renderer().global_arena, env_sampler)

	game.render_state.temp_resources.tony_mc_mapface = tony_mc_mapface
	game.render_state.temp_resources.dfg = dfg
	game.render_state.temp_resources.env = env
	game.render_state.temp_resources.mesh_image_sampler = TEMP_mesh_image_sampler
	game.render_state.temp_resources.font_image_sampler = font_image_sampler
	game.render_state.temp_resources.shadow_depth_sampler = shadow_depth_sampler
	game.render_state.temp_resources.env_sampler = env_sampler

	write_builtin_bindless_descriptors()
}

// TODO: Automate this shit
write_builtin_bindless_descriptors :: proc() {
	tony_mc_mapface := game.render_state.temp_resources.tony_mc_mapface
	dfg := game.render_state.temp_resources.dfg
	env := game.render_state.temp_resources.env
	mesh_image_sampler := game.render_state.temp_resources.mesh_image_sampler
	font_image_sampler := game.render_state.temp_resources.font_image_sampler
	shadow_depth_sampler := game.render_state.temp_resources.shadow_depth_sampler
	env_sampler := game.render_state.temp_resources.env_sampler

	gfx.write_descriptor_set(
		game.render_state.bindless_descriptor_set,
		{
			{
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = game.render_state.shadow_depth_image.image_view,
				image_layout = .DEPTH_READ_ONLY_OPTIMAL,
				array_index = SHADOW_ID,
			},
			{
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = tony_mc_mapface.image_view,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = TONY_MC_MAPFACE_ID,
			},
			{binding = 0, type = .SAMPLED_IMAGE, image_view = dfg.image_view, image_layout = .READ_ONLY_OPTIMAL, array_index = DFG_ID},
			{
				binding = 0,
				type = .SAMPLED_IMAGE,
				image_view = env.image_view,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = ENVIRONMENT_MAP_ID,
			},
			{
				binding = 1,
				type = .SAMPLER,
				sampler = mesh_image_sampler,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = DEFAULT_SAMPLER_ID,
			},
			{
				binding = 1,
				type = .SAMPLER,
				sampler = shadow_depth_sampler,
				image_layout = .DEPTH_READ_ONLY_OPTIMAL,
				array_index = SHADOW_SAMPLER_ID,
			},
			{
				binding = 1,
				type = .SAMPLER,
				sampler = font_image_sampler,
				image_layout = .READ_ONLY_OPTIMAL,
				array_index = FONT_SAMPLER_ID,
			},
			{binding = 1, type = .SAMPLER, sampler = env_sampler, image_layout = .READ_ONLY_OPTIMAL, array_index = ENVIRONMENT_SAMPLER_ID},
			{binding = 2, type = .STORAGE_IMAGE, image_view = gfx.renderer().resolve_image.image_view, image_layout = .GENERAL},
		},
	)
}

init_pipelines :: proc() {
	assert(sp.createGlobalSession(sp.API_VERSION, &game.render_state.global_session) == sp.OK)

	init_mesh_pipelines()
	init_skinning_pipelines()
	init_skybox_pipelines()
	init_tonemapper_pipelines()
}

init_mesh_pipelines :: proc() {
	game.render_state.mesh_pipeline_layout = gfx.create_pipeline_layout_pc(
		"Basic_Mesh_Pipeline_Layout",
		&game.render_state.bindless_descriptor_layout,
		GPUDrawPushConstants,
	)
	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.mesh_pipeline_layout)

	game.render_state.mesh_shader = add_shader("shaders/mesh.slang", proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
		return gfx.create_graphics_pipeline(
			name = "Basic_Mesh_Pipeline",
			pipeline_layout = game.render_state.mesh_pipeline_layout,
			shader = module,
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = {.BACK},
			front_face = .COUNTER_CLOCKWISE,
			depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
			color_format = gfx.renderer().draw_image.format,
			multisampling_samples = gfx.msaa_samples(),
		)
	})

	game.render_state.shadow_pipeline_layout = gfx.create_pipeline_layout_pc(
		"Shadow_Depth_Pipeline_Layout",
		&game.render_state.bindless_descriptor_layout,
		GPUDrawShadowDepthPushConstants,
	)
	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.shadow_pipeline_layout)

	game.render_state.mesh_shadow_shader = add_shader(
	"shaders/shadow_depth.slang",
	proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
		return gfx.create_graphics_pipeline(
			name = "Shadow_Depth_Pipeline",
			pipeline_layout = game.render_state.shadow_pipeline_layout,
			shader = module,
			vertex_entry = "vertex_main",
			fragment_entry = nil, // TODO: Only need vertex depth currently for shadow maps.
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = {},
			front_face = .COUNTER_CLOCKWISE,
			depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
		)
	},
	)
}

init_skinning_pipelines :: proc() {
	game.render_state.skinning_pipeline_layout = gfx.create_pipeline_layout_pc("Skinning", nil, GPUSkinningPushConstants, {.COMPUTE})
	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.skinning_pipeline_layout)

	game.render_state.skinning_shader = add_shader("shaders/skinning.slang", proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
		return gfx.create_compute_pipelines("Skinning", game.render_state.skinning_pipeline_layout, module)
	})
}

init_skybox_pipelines :: proc() {
	game.render_state.skybox_pipeline_layout = gfx.create_pipeline_layout_pc(
		"Skybox_Pipeline_Layout",
		&game.render_state.bindless_descriptor_layout,
		GPUSkyboxPushConstants,
	)
	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.skybox_pipeline_layout)

	game.render_state.skybox_shader = add_shader("shaders/skybox.slang", proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
		return gfx.create_graphics_pipeline(
			name = "Skybox_Pipeline",
			pipeline_layout = game.render_state.skybox_pipeline_layout,
			shader = module,
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = {.BACK},
			front_face = .COUNTER_CLOCKWISE,
			depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
			color_format = gfx.renderer().draw_image.format,
			multisampling_samples = gfx.msaa_samples(),
		)
	})
}

init_tonemapper_pipelines :: proc() {
	game.render_state.tonemapper_pipeline_layout = gfx.create_pipeline_layout(
		"Tonemapper_Pipeline_Layout",
		&game.render_state.bindless_descriptor_layout,
	)
	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.tonemapper_pipeline_layout)

	game.render_state.tonemapper_shader = add_shader("shaders/tonemapping.slang", proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
		return gfx.create_compute_pipelines("Tonemapper_Pipeline", game.render_state.tonemapper_pipeline_layout, module)
	})
}

GPUFontRendererPushConstants :: struct {
	atlas:     TextureId,
	sampler:   u32,
	instances: vk.DeviceAddress,
}

init_font_renderer :: proc() {
	font_state := &game.render_state.font_state

	fontstash.Init(&font_state.font_ctx, 512, 512, .BOTTOMLEFT)
	font_state.font_index = fontstash.AddFontPath(&font_state.font_ctx, "Default", "assets/fonts/Roboto-Regular.ttf")

	font_state.font_pip_layout = gfx.create_pipeline_layout_pc(
		"Font_Pipeline_Layout",
		&game.render_state.bindless_descriptor_layout,
		GPUFontRendererPushConstants,
	)
	gfx.defer_destroy(&gfx.renderer().global_arena, font_state.font_pip_layout)

	game.render_state.font_state.font_shader = add_shader("shaders/text.slang", proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
		return gfx.create_graphics_pipeline(
			name = "Font_Pipeline_Layout",
			pipeline_layout = game.render_state.font_state.font_pip_layout,
			shader = module,
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = {},
			front_face = .COUNTER_CLOCKWISE,
			blend_mode = .Alpha,
			depth = {format = gfx.renderer().depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
			color_format = gfx.renderer().draw_image.format,
			multisampling_samples = gfx.msaa_samples(),
		)
	})

	font_state.font_instance_buf = gfx.create_buffer(
		size_of(GPU_Font_Instance) * 512,
		{.TRANSFER_DST, .STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		.CPU_TO_GPU,
	)

	font_state.font_index_buf = gfx.create_buffer(size_of(u32) * 6, {.INDEX_BUFFER, .TRANSFER_DST}, .GPU_ONLY)
	gfx.staging_write_buffer_slice(&font_state.font_index_buf, []u32{2, 1, 0, 1, 2, 3})
}

init_buffers :: proc() {
	// Skybox 
	{
		mesh, ok := load_gpu_mesh_from_file("assets/meshes/static/skybox.glb")
		assert(ok)
		defer_destroy_gpu_mesh(&gfx.renderer().global_arena, mesh)
		game.render_state.skybox_mesh = mesh
	}

	for &frame in game.render_state.frame_data {
		// Global uniform buffer
		frame.global_uniform_buffer = gfx.create_buffer(size_of(GPUGlobalData), {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS}, .CPU_TO_GPU)
		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, frame.global_uniform_buffer)

		// Model matrices
		frame.model_matrices_buffer = gfx.create_buffer(size_of(Mat4x4) * 16_384, {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS}, .CPU_TO_GPU)
		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, frame.model_matrices_buffer)

		frame.cascade_matrices_buffer = gfx.create_buffer(
			size_of(Mat4x4) * NUM_CASCADES,
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)
		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, frame.cascade_matrices_buffer)

		frame.cascade_configs_buffer = gfx.create_buffer(
			size_of(GPUCascadeConfig) * NUM_CASCADES,
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)
		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, frame.cascade_configs_buffer)
	}

	comp_coeffs := process_sh_coefficients_from_cubemap_file("assets/gen/test_cubemap_ld.ktx2")
	// comp_coeffs := process_sh_coefficients_from_equirectangular_file("assets/gen/test_equirectangular.ktx2")

	environment := &game.render_state.global_uniform_data.environment

	// TODO: TEMP: Remove this at some point. Just testing volumes!
	ir_volume: Irradiance_Volume
	init_irradiance_volume(&ir_volume)

	game.render_state.scene_resources.point_light_buffer = gfx.create_buffer(
		size_of(GPU_Point_Light) * len(game.render_state.scene_resources.point_lights),
		{.TRANSFER_DST, .SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
		.GPU_ONLY,
	)

	environment^ = {
		sh_volume        = ir_volume.gpu_buffer.address,
		// sh_coeffs       = comp_coeffs,
		// sh_volume_size  = ir_volume.sh_volume_size,
		// sh_volume_scale = ir_volume.sh_volume_scale,
		point_lights     = game.render_state.scene_resources.point_light_buffer.address,
		num_point_lights = u32(len(game.render_state.scene_resources.point_lights)),
	}

	reserve(&game.render_state.model_matrices, 16_000)
}

get_shader :: proc(id: ShaderId) -> ^Shader {
	return &game.render_state.shaders[id]
}

add_shader :: proc(path: cstring, pipeline_create_callback: ShaderCreatePipelineCallback) -> ShaderId {
	shader := init_shader(path, pipeline_create_callback)

	id := ShaderId(u32(len(game.render_state.shaders)))
	append(&game.render_state.shaders, shader)

	return ShaderId(id)
}

defer_destroy_shader_id :: proc(arena: ^gfx.VulkanArena, shader_id: ShaderId) {
	defer_destroy_shader(arena, get_shader(shader_id)^)
}

check_shader_hotreload :: proc() -> (needs_reload: bool) {
	// TODO: SPEED: Maybe iter this across frames?
	for &shader in game.render_state.shaders {
		max_last_write_time: i64
		last_write_time, ok := os2.last_write_time_by_name(string(shader.path))
		max_last_write_time = last_write_time._nsec

		for path in shader.extra_files {
			last, k := os2.last_write_time_by_name(string(path))
			if last._nsec > max_last_write_time {
				max_last_write_time = last._nsec
			}
		}

		if shader.last_compile_time._nsec < max_last_write_time {
			shader.needs_recompile = true
			needs_reload = true
		}
	}

	return
}

hotreload_modified_shaders :: proc() -> bool {
	// TODO: SPEED: Maybe iter this across frames?
	for &shader in game.render_state.shaders {
		if shader.needs_recompile {
			ok := reload_shader_pipeline(&shader)

			shader.last_compile_time = time.now()
			shader.needs_recompile = false
			return ok
		}
	}

	return false
}

renderer_draw_text :: proc(
	text: string,
	pos: Vec2,
	size: f32 = 12,
	color := Vec3(1),
	blur: f32 = 0,
	spacing: f32 = 0,
	align_h: fontstash.AlignHorizontal = .LEFT,
	align_v: fontstash.AlignVertical = .BASELINE,
) {
	font_state := &game.render_state.font_state

	// Easier than dealing with fontstash state stack...
	state := fontstash.__getState(&font_state.font_ctx)
	state^ = {
		size    = size,
		blur    = blur,
		spacing = spacing,
		font    = 0,
		ah      = fontstash.AlignHorizontal(align_h),
		av      = fontstash.AlignVertical(align_v),
	}

	inv_screen := 1.0 / linalg.array_cast(transmute([2]u32)gfx.renderer().draw_extent, f32)

	for iter := fontstash.TextIterInit(&font_state.font_ctx, pos.x, pos.y, text); true; {
		quad: fontstash.Quad
		fontstash.TextIterNext(&font_state.font_ctx, &iter, &quad) or_break

		font_inst := GPU_Font_Instance {
			// Transform quads into NDC
			pos_min = (Vec2{quad.x0, quad.y0} * inv_screen) * 2.0 - 1.0,
			pos_max = (Vec2{quad.x1, quad.y1} * inv_screen) * 2.0 - 1.0,
			uv_min  = {quad.s0, quad.t0},
			uv_max  = {quad.s1, quad.t1},
			color   = {color.x, color.y, color.z, 1.0},
		}

		font_inst.pos_min.y *= -1
		font_inst.pos_max.y *= -1

		append(&font_state.font_instances, font_inst)
	}
}

draw :: proc() {
	scope_stat_time(.Render)
	renderer_draw_text("Testing!!!!", 30, 128, color = 0)

	when ODIN_DEBUG {
		if check_shader_hotreload() {
			gfx.vk_check(vk.DeviceWaitIdle(gfx.renderer().device))
			hotreload_start := time.now()
			if hotreload_modified_shaders() {
				fmt.println("Shaders hotreloaded in", time.since(hotreload_start))
			} else {
				fmt.println("Shaders failed to load!")
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

	{
		font_state := &game.render_state.font_state

		if len(font_state.font_instances) > 0 {
			gfx.write_buffer_slice(&font_state.font_instance_buf, font_state.font_instances[:])
		}

		atlas_size := UVec2{u32(font_state.font_ctx.width), u32(font_state.font_ctx.height)}
		dirty_texture :=
			font_state.font_ctx.dirtyRect[0] < font_state.font_ctx.dirtyRect[2] &&
			font_state.font_ctx.dirtyRect[1] < font_state.font_ctx.dirtyRect[3]

		if font_state.font_atlas_size != atlas_size {
			dirty_texture = true
			font_state.font_atlas_size = atlas_size

			vk.DeviceWaitIdle(gfx.renderer().device)

			if font_state.font_img.image != 0 {
				gfx.defer_destroy_gpu_image(&gfx.current_frame().arena, font_state.font_img)
			}

			font_state.font_img = gfx.create_gpu_image(
				.R8_UINT,
				{atlas_size.x, atlas_size.y, 1},
				{.TRANSFER_DST, .SAMPLED},
			)
			gfx.create_gpu_image_view(&font_state.font_img, {.COLOR})

			set_texture(font_state.font_img, FONT_ATLAS_ID)
		}

		if dirty_texture {
			gfx.staging_write_image_slice(&font_state.font_img, font_state.font_ctx.textureData)
		}

		font_state.font_ctx.state_count = 0
		fontstash.Reset(&font_state.font_ctx)
	}

	cmd := gfx.begin_command_buffer()

	update_buffers()

	// TODO: This updates every frame... probably bad?
	write_builtin_bindless_descriptors()

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
	gfx.transition_image(cmd, game.render_state.shadow_depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	for view, i in game.render_state.shadow_depth_attach_image_views {
		shadow_map_pass(cmd, u32(i))
	}
	// End shadow pass

	// Clear
	gfx.transition_image(cmd, gfx.renderer().draw_image.image, .UNDEFINED, .GENERAL)
	background_pass(cmd)

	// Begin mesh pass
	gfx.transition_image(cmd, gfx.renderer().draw_image.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)
	gfx.transition_image(cmd, gfx.renderer().depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	gfx.transition_image(cmd, game.render_state.shadow_depth_image.image, .DEPTH_ATTACHMENT_OPTIMAL, .DEPTH_READ_ONLY_OPTIMAL)
	if game.render_state.draw_skybox {
		skybox_pass(cmd)
	}
	geometry_pass(cmd)
	// End mesh pass

	{
		font_state := &game.render_state.font_state

		// Draw text
		if len(font_state.font_instances) > 0 {
			color_attachment := gfx.init_attachment_info(gfx.renderer().draw_image.image_view, nil, .GENERAL)
			depth_attachment := gfx.init_attachment_info(
				gfx.renderer().depth_image.image_view,
				&{depthStencil = {depth = 1.0}},
				.DEPTH_ATTACHMENT_OPTIMAL,
			)

			render_info := gfx.init_rendering_info(gfx.renderer().draw_extent, &color_attachment, &depth_attachment)
			vk.CmdBeginRendering(cmd, &render_info)
			gfx.set_viewport_and_scissor(cmd, gfx.renderer().draw_extent)

			vk.CmdBindPipeline(cmd, .GRAPHICS, get_shader(font_state.font_shader).pipeline)
			vk.CmdBindDescriptorSets(cmd, .GRAPHICS, font_state.font_pip_layout, 0, 1, &game.render_state.bindless_descriptor_set, 0, nil)

			vk.CmdBindIndexBuffer(cmd, font_state.font_index_buf.buffer, 0, .UINT32)

			vk.CmdPushConstants(
				cmd,
				font_state.font_pip_layout,
				{.VERTEX, .FRAGMENT},
				0,
				size_of(GPUFontRendererPushConstants),
				&GPUFontRendererPushConstants {
					atlas = FONT_ATLAS_ID,
					sampler = DEFAULT_SAMPLER_ID,
					instances = font_state.font_instance_buf.address,
				},
			)

			vk.CmdDrawIndexed(cmd, 6, u32(len(font_state.font_instances)), 0, 0, 0)
			clear(&font_state.font_instances)

			vk.CmdEndRendering(cmd)
		}
	}

	final_image: vk.Image
	switch game.view_state {
	case .SceneDepth:
		gfx.transition_image(cmd, gfx.renderer().depth_image.image, .DEPTH_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
		final_image = gfx.renderer().depth_image.image
	case .ShadowDepth:
		gfx.transition_image(cmd, game.render_state.shadow_depth_image.image, .DEPTH_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
		final_image = game.render_state.shadow_depth_image.image
	case .SceneColor:
		if gfx.msaa_enabled() {
			// Resolve MSAA
			gfx.transition_image(cmd, gfx.renderer().draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
			gfx.transition_image(cmd, gfx.renderer().resolve_image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

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

			gfx.transition_image(cmd, gfx.renderer().resolve_image.image, .TRANSFER_DST_OPTIMAL, .GENERAL)
			post_processing_pass(cmd)

			// Prepare swapchain image
			gfx.transition_image(cmd, gfx.renderer().resolve_image.image, .GENERAL, .TRANSFER_SRC_OPTIMAL)
			final_image = gfx.renderer().resolve_image.image
		} else {
			post_processing_pass(cmd)
			// Prepare swapchain image
			gfx.transition_image(cmd, gfx.renderer().draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
			final_image = gfx.renderer().draw_image.image
		}
	}

	gfx.copy_image_to_swapchain(cmd, final_image, gfx.renderer().draw_extent)

	gfx.submit(cmd)

	clear(&current_frame_game().mesh_draws)
	clear(&current_frame_game().skel_instances)
	clear(&game.render_state.model_matrices)
}

skinning_pass :: proc(cmd: vk.CommandBuffer, instance: ^SkeletalMeshInstance) {
	vk.CmdBindPipeline(cmd, .COMPUTE, get_shader(game.render_state.skinning_shader).pipeline)

	vk.CmdPushConstants(
		cmd,
		game.render_state.skinning_pipeline_layout,
		{.COMPUTE},
		0,
		size_of(GPUSkinningPushConstants),
		&GPUSkinningPushConstants {
			input_vertex_buffer = instance.skel.buffers.vertex_buffer.address,
			output_vertex_buffer = instance.preskinned_vertex_buffers[gfx.current_frame_index()].address,
			attrs = instance.skel.buffers.skel_vert_attrs_buffer.address,
			joint_matrices = instance.joint_matrices_buffers[gfx.current_frame_index()].address,
			vertex_count = instance.skel.buffers.vertex_count,
		},
	)

	vk.CmdDispatch(cmd, u32(math.ceil(f32(instance.skel.buffers.vertex_count) / 64.0)), 1, 1)
}

// TODO: Encode this as indirect draw args instead.
MeshDraw :: struct {
	vertex_buffer_address: vk.DeviceAddress,
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
	depth_attachment := gfx.init_attachment_info(image_view, &{depthStencil = {depth = 1.0}}, .DEPTH_ATTACHMENT_OPTIMAL)

	width := game.render_state.shadow_depth_image.extent.width
	height := game.render_state.shadow_depth_image.extent.height

	render_info := gfx.init_rendering_info({width, height}, nil, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	gfx.set_viewport_and_scissor(cmd, game.render_state.shadow_depth_image.extent)

	vk.CmdBindPipeline(cmd, .GRAPHICS, get_shader(game.render_state.mesh_shadow_shader).pipeline)
	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		game.render_state.mesh_pipeline_layout,
		0,
		1,
		&game.render_state.bindless_descriptor_set,
		0,
		nil,
	)

	for mesh_draw in current_frame_game().mesh_draws {
		vk.CmdBindIndexBuffer(cmd, mesh_draw.index_buffer, 0, .UINT32)

		vk.CmdPushConstants(
			cmd,
			game.render_state.shadow_pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			size_of(GPUDrawShadowDepthPushConstants),
			&GPUDrawShadowDepthPushConstants {
				vertex_buffer = mesh_draw.vertex_buffer_address,
				model_matrices = current_frame_game().model_matrices_buffer.address,
				global_data = current_frame_game().global_uniform_buffer.address,
				model_index = mesh_draw.model_index,
				cascade_index = cascade,
			},
		)

		vk.CmdDrawIndexed(cmd, mesh_draw.index_count, 1, 0, 0, 0)
	}

	vk.CmdEndRendering(cmd)
}

background_pass :: proc(cmd: vk.CommandBuffer) {
	clear_color := vk.ClearColorValue {
		float32 = {0, 0, 0, 1},
	}

	clear_range := gfx.init_image_subresource_range({.COLOR})

	vk.CmdClearColorImage(cmd, gfx.renderer().draw_image.image, .GENERAL, &clear_color, 1, &clear_range)
}

geometry_pass :: proc(cmd: vk.CommandBuffer) {
	// begin a render pass  connected to our draw image
	color_attachment := gfx.init_attachment_info(gfx.renderer().draw_image.image_view, nil, .GENERAL)
	depth_attachment := gfx.init_attachment_info(
		gfx.renderer().depth_image.image_view,
		&{depthStencil = {depth = 1.0}},
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

	// Start render pass.
	render_info := gfx.init_rendering_info(gfx.renderer().draw_extent, &color_attachment, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	gfx.set_viewport_and_scissor(cmd, gfx.renderer().draw_extent)

	vk.CmdBindPipeline(cmd, .GRAPHICS, get_shader(game.render_state.mesh_shader).pipeline)
	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		game.render_state.mesh_pipeline_layout,
		0,
		1,
		&game.render_state.bindless_descriptor_set,
		0,
		nil,
	)

	for mesh_draw in current_frame_game().mesh_draws {
		vk.CmdBindIndexBuffer(cmd, mesh_draw.index_buffer, 0, .UINT32)

		vk.CmdPushConstants(
			cmd,
			game.render_state.mesh_pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			size_of(GPUDrawPushConstants),
			&GPUDrawPushConstants {
				global_data_buffer = current_frame_game().global_uniform_buffer.address,
				vertex_buffer = mesh_draw.vertex_buffer_address,
				model_matrices = current_frame_game().model_matrices_buffer.address,
				materials = game.render_state.scene_resources.materials_buffer.address,
				model_index = mesh_draw.model_index,
				material_index = mesh_draw.material_index,
				num_cascades = NUM_CASCADES,
			},
		)

		vk.CmdDrawIndexed(cmd, mesh_draw.index_count, 1, 0, 0, 0)
	}

	vk.CmdEndRendering(cmd)
}

skybox_pass :: proc(cmd: vk.CommandBuffer) {
	// begin a render pass  connected to our draw image
	color_attachment := gfx.init_attachment_info(gfx.renderer().draw_image.image_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
	depth_attachment := gfx.init_attachment_info(
		gfx.renderer().depth_image.image_view,
		&{depthStencil = {depth = 1.0}},
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

	// Start render pass.
	render_info := gfx.init_rendering_info(gfx.renderer().draw_extent, &color_attachment, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	gfx.set_viewport_and_scissor(cmd, gfx.renderer().draw_extent)

	vk.CmdBindPipeline(cmd, .GRAPHICS, get_shader(game.render_state.skybox_shader).pipeline)
	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		game.render_state.skybox_pipeline_layout,
		0,
		1,
		&game.render_state.bindless_descriptor_set,
		0,
		nil,
	)
	vk.CmdBindIndexBuffer(cmd, game.render_state.skybox_mesh.index_buffer.buffer, 0, .UINT32)

	vk.CmdPushConstants(
		cmd,
		game.render_state.skybox_pipeline_layout,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(GPUSkyboxPushConstants),
		&GPUSkyboxPushConstants {
			vertex_buffer = game.render_state.skybox_mesh.vertex_buffer.address,
			global_data_buffer = current_frame_game().global_uniform_buffer.address,
		},
	)

	vk.CmdDrawIndexed(cmd, game.render_state.skybox_mesh.index_count, 1, 0, 0, 0)
	vk.CmdEndRendering(cmd)
}

post_processing_pass :: proc(cmd: vk.CommandBuffer) {
	vk.CmdBindPipeline(cmd, .COMPUTE, get_shader(game.render_state.tonemapper_shader).pipeline)
	vk.CmdBindDescriptorSets(
		cmd,
		.COMPUTE,
		game.render_state.tonemapper_pipeline_layout,
		0,
		1,
		&game.render_state.bindless_descriptor_set,
		0,
		nil,
	)

	vk.CmdDispatch(
		cmd,
		u32(math.ceil(f32(gfx.renderer().draw_extent.width) / 16.0)),
		u32(math.ceil(f32(gfx.renderer().draw_extent.height) / 16.0)),
		1,
	)
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

	global_uniform_data.projection_matrix = get_current_projection_matrix()
	global_uniform_data.view_matrix = get_current_view_matrix()

	global_uniform_data.sun_color = game.state.environment.sun_color
	global_uniform_data.sky_color = game.state.environment.sky_color

	global_uniform_data.camera_pos = player != nil ? player.translation : {0, 0, 0}
	global_uniform_data.sun_direction = game.state.environment.sun_direction

	global_uniform_data.environment.num_point_lights = auto_cast len_entities(Point_Light)

	global_uniform_data.cascade_world_to_shadows = current_frame_game().cascade_matrices_buffer.address
	global_uniform_data.cascade_configs = current_frame_game().cascade_configs_buffer.address

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

	for &point_light, i in get_entities(Point_Light) {
		if i >= len(game.render_state.scene_resources.point_lights) do break
		game.render_state.scene_resources.point_lights[i] = point_light_to_gpu(point_light)
	}

	gfx.staging_write_buffer_slice(
		&game.render_state.scene_resources.point_light_buffer,
		game.render_state.scene_resources.point_lights[:],
	)

	calculate_shadow_view_projection_matrices()
}
