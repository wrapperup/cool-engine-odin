package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:os/os2"
import "core:time"

import vk "vendor:vulkan"

import sp "deps:odin-slang/slang"
import vma "deps:odin-vma"

import gfx "gfx"

SHADOW_ID: u32 : 0
TONY_MC_MAPFACE_ID: u32 : 1
DFG_ID: u32 : 2
ENVIRONMENT_MAP_ID: u32 : 3
TEST_SH_0_3_3D_ID: u32 : 4
TEST_SH_4_7_3D_ID: u32 : 5
TEST_SH_8_9_3D_ID: u32 : 6

DEFAULT_SAMPLER_ID: u32 : 0
SHADOW_SAMPLER_ID: u32 : 1
ENVIRONMENT_SAMPLER_ID: u32 : 2

RESOLVED_IMAGE_ID: u32 : 0

MAX_BINDLESS_IMAGES :: 100
RESERVED_BINDLESS_IMAGES_COUNT :: 10
MAX_BINDLESS_SAMPLERS :: 32

@(ShaderShared)
GPUDrawPushConstants :: struct {
	global_data_buffer: vk.DeviceAddress,
	vertex_buffer:      vk.DeviceAddress,
	model_matrices:     vk.DeviceAddress,
	materials:          vk.DeviceAddress,
	model_index:        u32,
	material_index:     MaterialId,
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
	view_projection_matrix: hlsl.float4x4,
	vertex_buffer:          vk.DeviceAddress,
	global_data_buffer:     vk.DeviceAddress,
}

// TODO: Make this into proper assets?
TextureId :: distinct u32
MaterialId :: distinct u32
ShaderId :: distinct u32

@(ShaderShared)
GPUMaterial :: struct {
	base_color_id:            TextureId,
	normal_map_id:            TextureId,
	ao_roughness_metallic_id: TextureId,
}

@(ShaderShared)
GPUEnvironment :: struct {
	// sh_volume_size:  [3]u32,
	// pad_0:           u32,
	// sh_volume_scale: [3]f32,
	// pad_1:           u32,
	sh_volume: vk.DeviceAddress, // []Sh_Coefficients
}

// 256 bytes is the maximum allowed in a push constant on a 3090Ti
// TODO: move matrices out into uniform
#assert(size_of(GPUDrawPushConstants) <= 256)
#assert(size_of(GPUSkinningPushConstants) <= 256)
#assert(size_of(GPUSkyboxPushConstants) <= 256)

@(ShaderShared)
GPUGlobalData :: struct {
	view_projection_matrix:       hlsl.float4x4,
	view_projection_i_matrix:     hlsl.float4x4,
	sun_view_projection_matrix:   hlsl.float4x4,
	sun_view_projection_i_matrix: hlsl.float4x4,
	sun_color:                    hlsl.float3,
	bias:                         f32,
	sky_color:                    hlsl.float3,
	pad_0:                        f32,
	camera_pos:                   hlsl.float3,
	pad_1:                        f32,
	sun_pos:                      hlsl.float3,
	pad_2:                        f32,
	environment:                  GPUEnvironment,
}

GameFrameData :: struct {
	global_uniform_buffer:         gfx.GPUBuffer,
	model_matrices_buffer:         gfx.GPUBuffer,
	test_preskinned_vertex_buffer: gfx.GPUBuffer,
	mesh_draws:                    [dynamic]MeshDraw,
	skel_instances:                [dynamic]^SkeletalMeshInstance,
}

RenderState :: struct {
	frame_data:                 [gfx.FRAME_OVERLAP]GameFrameData,

	// Bindless textures, etc
	bindless_descriptor_layout: vk.DescriptorSetLayout,
	bindless_descriptor_set:    vk.DescriptorSet,
	global_uniform_data:        GPUGlobalData,
	scene_resources:            struct {
		bindless_textures:            [dynamic]gfx.GPUImage,
		bindless_texture_start_index: u32, // 0-10 is for reserved internal textures
		materials:                    [dynamic]GPUMaterial,
		materials_buffer:             gfx.GPUBuffer,
	},
	shaders:                    [dynamic]Shader,
	global_session:             ^sp.IGlobalSession,

	// Mesh pipelines
	mesh_pipeline_layout:       vk.PipelineLayout,
	mesh_shader:                ShaderId,
	model_matrices:             [dynamic]hlsl.float4x4,

	// Skeletal mesh pipelines
	skinning_pipeline_layout:   vk.PipelineLayout,
	skinning_shader:            ShaderId,

	// Shadow pipelines
	mesh_shadow_shader:         ShaderId,
	shadow_depth_image:         gfx.GPUImage,

	// Tonemapper pipelines
	tonemapper_shader:          ShaderId,
	tonemapper_pipeline_layout: vk.PipelineLayout,

	// Skybox pipelines
	skybox_pipeline_layout:     vk.PipelineLayout,
	skybox_shader:              ShaderId,
	skybox_mesh:                GPUMeshBuffers,
	draw_skybox:                bool,
}

current_frame_game :: proc() -> ^GameFrameData {
	return &game.render_state.frame_data[gfx.current_frame_index()]
}

//// INITIALIZATION
init_game_renderer :: proc() {
	init_shadow_map({4096, 4096, 1})
	init_descriptors()
	init_pipelines()
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

	base_color_id = add_texture(gfx.load_image_from_file("assets/textures/materialball2/basecolor.ktx2"))
	normal_map_id = add_texture(gfx.load_image_from_file("assets/textures/materialball2/normalmap.ktx2"))
	proughness_metallic_ao_id = add_texture(gfx.load_image_from_file("assets/textures/materialball2/rma.ktx2"))

	add_material({base_color_id = base_color_id, normal_map_id = normal_map_id, ao_roughness_metallic_id = proughness_metallic_ao_id})
}

add_texture :: proc(image: gfx.GPUImage) -> TextureId {
	scene_resources := &game.render_state.scene_resources
	texture_id := TextureId(scene_resources.bindless_texture_start_index + u32(len(scene_resources.bindless_textures)))

	append(&scene_resources.bindless_textures, image)

	fmt.println("id:", texture_id)

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

add_material :: proc(material: GPUMaterial) -> MaterialId {
	scene_resources := &game.render_state.scene_resources
	material_id := MaterialId(len(scene_resources.materials))

	append(&scene_resources.materials, material)

	gfx.staging_write_buffer_slice(&scene_resources.materials_buffer, scene_resources.materials[:])

	return material_id
}

init_shadow_map :: proc(extent: vk.Extent3D) {
	game.render_state.shadow_depth_image = gfx.create_image(.D32_SFLOAT, extent, {.DEPTH_STENCIL_ATTACHMENT, .SAMPLED})
	gfx.create_image_view(&game.render_state.shadow_depth_image, {.DEPTH})

	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.shadow_depth_image.image_view)
	gfx.defer_destroy(
		&gfx.renderer().global_arena,
		game.render_state.shadow_depth_image.image,
		game.render_state.shadow_depth_image.allocation,
	)
}

init_descriptors :: proc() {
	init_bindless_descriptors()
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
	TEMP_mesh_image_sampler := gfx.create_sampler(.LINEAR, .REPEAT)
	gfx.defer_destroy(&gfx.renderer().global_arena, TEMP_mesh_image_sampler)

	// Shadow Depth Texture Sampler
	shadow_depth_sampler := gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE, .LESS_OR_EQUAL)
	gfx.defer_destroy(&gfx.renderer().global_arena, shadow_depth_sampler)

	env_sampler := gfx.create_sampler(.LINEAR, .CLAMP_TO_EDGE, max_lod = 8.0)
	gfx.defer_destroy(&gfx.renderer().global_arena, env_sampler)

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
				sampler = TEMP_mesh_image_sampler,
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
		&game.render_state.bindless_descriptor_layout,
		GPUDrawPushConstants,
	)
	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.mesh_pipeline_layout)

	game.render_state.mesh_shader = add_shader(
		"shaders/mesh.slang",
		{"vertex_main", "fragment_main"},
		proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
			return gfx.create_graphics_pipeline(
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
		},
	)

	game.render_state.mesh_shadow_shader = add_shader(
	"shaders/mesh.slang",
	{"vertex_main", "fragment_main"},
	proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
		return gfx.create_graphics_pipeline(
			pipeline_layout = game.render_state.mesh_pipeline_layout,
			shader = module,
			vertex_entry = "vertex_shadow_main",
			fragment_entry = nil, // We don't need a fragment shader since we're just rendering vertex depth (currently).
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
	game.render_state.skinning_pipeline_layout = gfx.create_pipeline_layout_pc(nil, GPUSkinningPushConstants, {.COMPUTE})
	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.skinning_pipeline_layout)

	game.render_state.skinning_shader = add_shader(
		"shaders/skinning.slang",
		{"compute_main"},
		proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
			return gfx.create_compute_pipelines(game.render_state.skinning_pipeline_layout, module)
		},
	)
}

init_skybox_pipelines :: proc() {
	game.render_state.skybox_pipeline_layout = gfx.create_pipeline_layout_pc(
		&game.render_state.bindless_descriptor_layout,
		GPUSkyboxPushConstants,
	)
	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.skybox_pipeline_layout)

	game.render_state.skybox_shader = add_shader(
		"shaders/skybox.slang",
		{"vertex_main", "fragment_main"},
		proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
			return gfx.create_graphics_pipeline(
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
		},
	)
}

init_tonemapper_pipelines :: proc() {
	game.render_state.tonemapper_pipeline_layout = gfx.create_pipeline_layout(&game.render_state.bindless_descriptor_layout)
	gfx.defer_destroy(&gfx.renderer().global_arena, game.render_state.tonemapper_pipeline_layout)

	game.render_state.tonemapper_shader = add_shader(
		"shaders/tonemapping.slang",
		{"compute_main"},
		proc(module: vk.ShaderModule) -> (vk.Pipeline, bool) {
			return gfx.create_compute_pipelines(game.render_state.tonemapper_pipeline_layout, module)
		},
	)
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
		frame.model_matrices_buffer = gfx.create_buffer(
			size_of(hlsl.float4x4) * 16_384,
			{.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
			.CPU_TO_GPU,
		)
		gfx.defer_destroy_buffer(&gfx.renderer().global_arena, frame.model_matrices_buffer)
	}

	comp_coeffs := process_sh_coefficients_from_cubemap_file("assets/gen/test_cubemap_ld.ktx2")
	// comp_coeffs := process_sh_coefficients_from_equirectangular_file("assets/gen/test_equirectangular.ktx2")

	environment := &game.render_state.global_uniform_data.environment

	// TODO: TEMP: Remove this at some point. Just testing volumes!
	ir_volume: Irradiance_Volume
	init_irradiance_volume(&ir_volume)

	environment^ = {
		sh_volume = ir_volume.gpu_buffer.address,
		// sh_coeffs       = comp_coeffs,
		// sh_volume_size  = ir_volume.sh_volume_size,
		// sh_volume_scale = ir_volume.sh_volume_scale,
	}

	reserve(&game.render_state.model_matrices, 16_000)
}

get_shader :: proc(id: ShaderId) -> ^Shader {
	return &game.render_state.shaders[id]
}

add_shader :: proc(path: cstring, entrypoints: []cstring, pipeline_create_callback: ShaderCreatePipelineCallback) -> ShaderId {
	shader := init_shader(path, entrypoints, pipeline_create_callback)

	id := ShaderId(u32(len(game.render_state.shaders)))
	append(&game.render_state.shaders, shader)

	return ShaderId(id)
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

hotreload_modified_shaders :: proc() {
	// TODO: SPEED: Maybe iter this across frames?
	for &shader in game.render_state.shaders {
		if shader.needs_recompile {
			if reload_shader_pipeline(&shader) {
				shader.last_compile_time = time.now()
				shader.needs_recompile = false
			}
			return
		}
	}

	return
}

//// RENDERING
draw :: proc() {
	scope_stat_time(.Render)

	when ODIN_DEBUG {
		if check_shader_hotreload() {
			gfx.vk_check(vk.DeviceWaitIdle(gfx.renderer().device))
			hotreload_modified_shaders()
			fmt.println("Shaders hotreloaded!")
		}
	}

	// TEMP: test draw command
	for &ball in get_entities(Ball) {
		draw_skeletal_mesh(&ball.skel_mesh_instance, ball.material, ball.translation, ball.rotation, 1)
	}

	for static_mesh in get_entities(StaticMesh) {
		draw_mesh(static_mesh.mesh, static_mesh.material, static_mesh.translation, static_mesh.rotation, 1)
	}

	cmd := gfx.begin_command_buffer()

	update_buffers()

	// Begin Skinning pass
	for instance in current_frame_game().skel_instances {
		// This feels suck?
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
	shadow_map_pass(cmd)
	// End shadow pass

	// Clear
	gfx.transition_image(cmd, gfx.renderer().draw_image.image, .UNDEFINED, .GENERAL)
	background_pass(cmd)

	// Begin geometry pass
	gfx.transition_image(cmd, gfx.renderer().draw_image.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)
	gfx.transition_image(cmd, gfx.renderer().depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)
	gfx.transition_image(cmd, game.render_state.shadow_depth_image.image, .DEPTH_ATTACHMENT_OPTIMAL, .DEPTH_READ_ONLY_OPTIMAL)
	if game.render_state.draw_skybox {
		skybox_pass(cmd)
	}
	geometry_pass(cmd)
	// End skeletal mesh pass

	// Begin skybox pass
	// End skybox pass

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
			ex := gfx.renderer().draw_extent

			// Resolve MSAA
			gfx.transition_image(cmd, gfx.renderer().draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
			gfx.transition_image(cmd, gfx.renderer().resolve_image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

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

	skinning_pc := GPUSkinningPushConstants {
		input_vertex_buffer  = instance.skel.buffers.vertex_buffer.address,
		output_vertex_buffer = instance.preskinned_vertex_buffers[gfx.current_frame_index()].address,
		attrs                = instance.skel.buffers.skel_vert_attrs_buffer.address,
		joint_matrices       = instance.joint_matrices_buffers[gfx.current_frame_index()].address,
		vertex_count         = instance.skel.buffers.vertex_count,
	}

	vk.CmdPushConstants(cmd, game.render_state.skinning_pipeline_layout, {.COMPUTE}, 0, size_of(GPUSkinningPushConstants), &skinning_pc)

	vk.CmdDispatch(cmd, u32(math.ceil(f32(instance.skel.buffers.vertex_count) / 64.0)), 1, 1)
}

MeshDraw :: struct {
	vertex_buffer_address: vk.DeviceAddress,
	index_buffer:          vk.Buffer,
	index_count:           u32,
	model_index:           u32,
	material_index:        MaterialId,
}

cmd_mesh_draw :: proc(cmd: vk.CommandBuffer, mesh_draw: MeshDraw) {
	vk.CmdBindIndexBuffer(cmd, mesh_draw.index_buffer, 0, .UINT32)

	push_constants := GPUDrawPushConstants {
		vertex_buffer      = mesh_draw.vertex_buffer_address,
		global_data_buffer = current_frame_game().global_uniform_buffer.address,
		model_matrices     = current_frame_game().model_matrices_buffer.address,
		materials          = game.render_state.scene_resources.materials_buffer.address,
		model_index        = mesh_draw.model_index,
		material_index     = mesh_draw.material_index,
	}

	vk.CmdPushConstants(
		cmd,
		game.render_state.mesh_pipeline_layout,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(GPUDrawPushConstants),
		&push_constants,
	)

	vk.CmdDrawIndexed(cmd, mesh_draw.index_count, 1, 0, 0, 0)
}

draw_mesh :: proc(mesh: GPUMeshBuffers, material: MaterialId, translation: [3]f32, rotation: quaternion128, scale: [3]f32) {
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
	translation: [3]f32,
	rotation: quaternion128,
	scale: [3]f32,
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

shadow_map_pass :: proc(cmd: vk.CommandBuffer) {
	depth_attachment := gfx.init_attachment_info(
		game.render_state.shadow_depth_image.image_view,
		&{depthStencil = {depth = 1.0}},
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

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
		cmd_mesh_draw(cmd, mesh_draw)
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
		cmd_mesh_draw(cmd, mesh_draw)
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

	player := get_entity(game.state.player_id)

	aspect_ratio := f32(game.window_extent.x) / f32(game.window_extent.y)

	rotation := linalg.matrix4_from_quaternion(player != nil ? player.rotation : {})

	view_matrix := linalg.inverse(rotation)

	projection_matrix := gfx.matrix4_infinite_perspective_z0_f32(
		linalg.to_radians(player != nil ? player.camera_fov_deg : 0),
		aspect_ratio,
		0.1,
	)
	projection_matrix[1][1] *= -1.0

	view_projection_matrix := projection_matrix * view_matrix

	push_constants: GPUSkyboxPushConstants
	push_constants.vertex_buffer = game.render_state.skybox_mesh.vertex_buffer.address
	push_constants.view_projection_matrix = view_projection_matrix
	push_constants.global_data_buffer = current_frame_game().global_uniform_buffer.address

	vk.CmdPushConstants(
		cmd,
		game.render_state.skybox_pipeline_layout,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(GPUSkyboxPushConstants),
		&push_constants,
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

update_buffers :: proc() {
	global_uniform_data := &game.render_state.global_uniform_data
	player := get_entity(game.state.player_id)

	// Camera matrices
	global_uniform_data.view_projection_matrix = get_projection_matrix(player) * get_view_matrix(player)
	global_uniform_data.view_projection_i_matrix = linalg.matrix4_inverse(global_uniform_data.view_projection_matrix)

	// Global sun matrices
	{
		sun_view_matrix := linalg.matrix4_look_at_f32(game.state.environment.sun_pos, game.state.environment.sun_target, {0.0, 1.0, 0.0})
		sun_projection_matrix := gfx.matrix_ortho3d_z0_f32(-50, 50, -50, 50, 0.1, 500.0)
		sun_projection_matrix[1][1] *= -1.0

		global_uniform_data.sun_view_projection_matrix = sun_projection_matrix * sun_view_matrix

		global_uniform_data.view_projection_i_matrix = linalg.matrix4_inverse(global_uniform_data.view_projection_matrix)
	}

	global_uniform_data.sun_color = game.state.environment.sun_color
	global_uniform_data.sky_color = game.state.environment.sky_color
	global_uniform_data.bias = game.state.environment.bias

	global_uniform_data.camera_pos = hlsl.float3(player != nil ? player.translation : [3]f32{0, 0, 0})
	global_uniform_data.sun_pos = hlsl.float3(game.state.environment.sun_pos)

	gfx.write_buffer(&current_frame_game().global_uniform_buffer, global_uniform_data)

	gfx.write_buffer_slice(&current_frame_game().model_matrices_buffer, game.render_state.model_matrices[:])

	for &ball in get_entities(Ball) {
		gfx.write_buffer_slice(
			&ball.skel_mesh_instance.joint_matrices_buffers[gfx.current_frame_index()],
			ball.skel_animator.calc_joints[:],
		)
	}
}
