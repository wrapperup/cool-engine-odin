package game

import "core:math"

import vk "vendor:vulkan"

import "gfx"

@(private = "file")
GPUPtr :: gfx.GPUPtr
@(private = "file")
ImageId :: gfx.ImageId

@(shader_shared)
GPUDDGITracePush :: struct #max_field_align(16) {
	volume:     GPUPtr(GPUDDGIVolume),
	geometries: GPUPtr(GPUGeometry),
	materials:  GPUPtr(GPUMaterial),
	global:     GPUPtr(GPUGlobalData),
	radiance:   GPUPtr(Vec4),
	tlas:       vk.DeviceAddress `AccelerationStructure`,
}

@(shader_shared)
GPUDDGIUpdatePush :: struct #max_field_align(16) {
	volume:     GPUPtr(GPUDDGIVolume),
	radiance:   GPUPtr(Vec4),
	irradiance: ImageId `RWImage2D`,
}

@(shader_shared)
GPUDDGIDebugAtlasPush :: struct #max_field_align(16) {
	volume:    GPUPtr(GPUDDGIVolume),
	out_image: ImageId `RWImage2D`,
}

@(shader_shared)
GPUDDGIProbePush :: struct #max_field_align(16) {
	global:        GPUPtr(GPUGlobalData),
	volume:        GPUPtr(GPUDDGIVolume),
	vertex_buffer: GPUPtr(Vertex),
	probe_radius:  f32,
}

DDGIRenderPass :: struct {
	trace_pipeline:         ^gfx.ComputePipeline,
	update_pipeline:        ^gfx.ComputePipeline,
	border_pipeline:        ^gfx.ComputePipeline,
	depth_update_pipeline:  ^gfx.ComputePipeline,
	depth_border_pipeline:  ^gfx.ComputePipeline,
	relocate_pipeline:      ^gfx.ComputePipeline,
	debug_pipeline:         ^gfx.ComputePipeline,
	probe_pipeline:         ^gfx.GraphicsPipeline,
	volumes_buffer:         gfx.GPUBuffer(GPUDDGIVolume),
	debug_volume:           i32,
	probe_vbuf:             gfx.GPUBuffer(Vertex),
	probe_ibuf:             gfx.GPUBuffer(u32),
	probe_index_count:      u32,
	draw_probes:            bool,
	draw_reflection_probes: bool,
}

init_ddgi_rp :: proc() {
	ddgi_rp := &game.render_state.ddgi_rp

	ddgi_rp.trace_pipeline = add_compute_shader("shaders/ddgi_trace.slang", proc(module: vk.ShaderModule) -> gfx.ComputePipeline {
		return gfx.create_compute_pipeline("DDGI_Trace", module, GPUDDGITracePush)
	})
	ddgi_rp.update_pipeline = add_compute_shader("shaders/ddgi_update.slang", proc(module: vk.ShaderModule) -> gfx.ComputePipeline {
		return gfx.create_compute_pipeline("DDGI_Update", module, GPUDDGIUpdatePush)
	})
	ddgi_rp.border_pipeline = add_compute_shader("shaders/ddgi_border.slang", proc(module: vk.ShaderModule) -> gfx.ComputePipeline {
		return gfx.create_compute_pipeline("DDGI_Border", module, GPUDDGIUpdatePush)
	})
	ddgi_rp.depth_update_pipeline = add_compute_shader(
		"shaders/ddgi_update_depth.slang",
		proc(module: vk.ShaderModule) -> gfx.ComputePipeline {
			return gfx.create_compute_pipeline("DDGI_Depth_Update", module, GPUDDGIUpdatePush)
		},
	)
	ddgi_rp.depth_border_pipeline = add_compute_shader(
		"shaders/ddgi_border_depth.slang",
		proc(module: vk.ShaderModule) -> gfx.ComputePipeline {
			return gfx.create_compute_pipeline("DDGI_Depth_Border", module, GPUDDGIUpdatePush)
		},
	)
	ddgi_rp.relocate_pipeline = add_compute_shader("shaders/ddgi_relocate.slang", proc(module: vk.ShaderModule) -> gfx.ComputePipeline {
		return gfx.create_compute_pipeline("DDGI_Relocate", module, GPUDDGIUpdatePush)
	})
	ddgi_rp.debug_pipeline = add_compute_shader("shaders/ddgi_debug_atlas.slang", proc(module: vk.ShaderModule) -> gfx.ComputePipeline {
		return gfx.create_compute_pipeline("DDGI_Debug_Atlas", module, GPUDDGIDebugAtlasPush)
	})
	ddgi_rp.probe_pipeline = add_graphics_shader("shaders/ddgi_debug_probes.slang", proc(module: vk.ShaderModule) -> gfx.GraphicsPipeline {
		return gfx.create_graphics_pipeline(
			name = "DDGI_Debug_Probes",
			shader = module,
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = {},
			front_face = .COUNTER_CLOCKWISE,
			depth = {format = gfx.r_ctx.depth_image.format, compare_op = .LESS_OR_EQUAL, write_enabled = true},
			color_format = gfx.r_ctx.draw_image.format,
			multisampling_samples = gfx.msaa_samples(),
			push_constants = GPUDDGIProbePush,
		)
	})

	ddgi_rp.volumes_buffer = gfx.create_buffer(GPUDDGIVolume, MAX_DDGI_VOLUMES, .DynUniform)
	gfx.defer_destroy(&gfx.r_ctx.global_arena, ddgi_rp.volumes_buffer)
	ddgi_init_debug_sphere()
}

// Generates a UV sphere (positions == normals, unit radius).
@(private = "file")
ddgi_make_sphere :: proc(rings, sectors: int) -> ([]Vertex, []u32) {
	verts := make([dynamic]Vertex)
	indices := make([dynamic]u32)
	for r in 0 ..= rings {
		theta := f32(r) / f32(rings) * math.PI
		st := math.sin(theta)
		ct := math.cos(theta)
		for s in 0 ..= sectors {
			phi := f32(s) / f32(sectors) * 2.0 * math.PI
			n := Vec3{st * math.cos(phi), ct, st * math.sin(phi)}
			append(&verts, Vertex{position = {n.x, n.y, n.z}, normal = {n.x, n.y, n.z}})
		}
	}
	for r in 0 ..< rings {
		for s in 0 ..< sectors {
			i0 := u32(r * (sectors + 1) + s)
			i1 := u32(r * (sectors + 1) + s + 1)
			i2 := u32((r + 1) * (sectors + 1) + s)
			i3 := u32((r + 1) * (sectors + 1) + s + 1)
			append(&indices, i0, i2, i1, i1, i2, i3)
		}
	}
	return verts[:], indices[:]
}

ddgi_init_debug_sphere :: proc() {
	rp := &game.render_state.ddgi_rp
	verts, indices := ddgi_make_sphere(12, 16)
	defer delete(verts)
	defer delete(indices)

	rp.probe_vbuf = gfx.create_buffer(Vertex, len(verts))
	rp.probe_ibuf = gfx.create_buffer(u32, len(indices), .Index)
	gfx.defer_destroy(&gfx.r_ctx.global_arena, rp.probe_vbuf)
	gfx.defer_destroy(&gfx.r_ctx.global_arena, rp.probe_ibuf)
	gfx.staging_write_buffer_slice(&rp.probe_vbuf, verts)
	gfx.staging_write_buffer_slice(&rp.probe_ibuf, indices)
	rp.probe_index_count = u32(len(indices))
}

// Overlay: draws an instanced sphere per probe into the HDR scene (after geometry_pass),
// each shaded by its own irradiance. Depth-tested against the scene.
ddgi_debug_probes_pass :: proc(cmd: vk.CommandBuffer, volume: ^DDGI_Volume_Resources) {
	rp := &game.render_state.ddgi_rp
	gfx.cmd_begin_rendering(
		cmd,
		area = gfx.r_ctx.draw_extent,
		color_attachment = &{view = gfx.r_ctx.draw_image.image_view, layout = .COLOR_ATTACHMENT_OPTIMAL},
		depth_attachment = &{view = gfx.r_ctx.depth_image.image_view, layout = .DEPTH_ATTACHMENT_OPTIMAL},
	)
	gfx.set_viewport_and_scissor(cmd, gfx.r_ctx.draw_extent)
	gfx.cmd_bind_pipeline(cmd, rp.probe_pipeline)
	gfx.cmd_bind_index_buffer(cmd, rp.probe_ibuf.buffer)
	gfx.cmd_push_constants(
		cmd,
		GPUDDGIProbePush {
			global = current_frame_game().global_buffer.ptr,
			volume = volume.config_buffer.ptr,
			vertex_buffer = rp.probe_vbuf.ptr,
			probe_radius = 0.3,
		},
	)
	counts := volume.gpu.grid_counts
	gfx.cmd_draw_indexed(cmd, rp.probe_index_count, instance_count = counts[0] * counts[1] * counts[2])
	gfx.cmd_end_rendering(cmd)
}

// Trace + update for the volume, recorded into `cmd`. Uses the per-frame scene TLAS.
ddgi_update_volume :: proc(cmd: vk.CommandBuffer, volume: ^DDGI_Volume_Resources) {
	counts := volume.gpu.grid_counts
	num_probes := counts[0] * counts[1] * counts[2]

	// Advance the ray set and push the config.
	volume.gpu.frame_index += 1
	gfx.write_buffer(&volume.config_buffer, &volume.gpu)

	// Pass A: trace.
	gfx.cmd_bind_pipeline(cmd, game.render_state.ddgi_rp.trace_pipeline)
	gfx.cmd_push_constants(
		cmd,
		GPUDDGITracePush {
			volume = volume.config_buffer.ptr,
			geometries = current_frame_game().rt.geometries_buffer.ptr,
			materials = game.render_state.scene_resources.materials_buffer.ptr,
			global = current_frame_game().global_buffer.ptr,
			radiance = volume.radiance_buffer.ptr,
			tlas = current_frame_game().rt.tlas.address,
		},
	)
	vk.CmdDispatch(cmd, num_probes, 1, 1)

	// radiance write -> read barrier before the update integrates it.
	gfx.transition_buffer(cmd, volume.radiance_buffer, {.SHADER_WRITE}, {.SHADER_READ}, gfx.r_ctx.graphics_queue_family)

	// Pass B: update irradiance atlas.
	gfx.cmd_bind_pipeline(cmd, game.render_state.ddgi_rp.update_pipeline)
	gfx.cmd_push_constants(
		cmd,
		GPUDDGIUpdatePush{volume = volume.config_buffer.ptr, radiance = volume.radiance_buffer.ptr, irradiance = volume.gpu.irradiance},
	)
	vk.CmdDispatch(cmd, num_probes, 1, 1)

	// interior write -> read before the border copy reads edge texels.
	gfx.image_barrier(
		cmd,
		{
			image      = &volume.irradiance,
			src_access = .ComputeShaderWrite,
			dst_access = .ComputeShaderRead,
		},
	)

	// Pass B2: octahedral border copy (seamless sampling).
	gfx.cmd_bind_pipeline(cmd, game.render_state.ddgi_rp.border_pipeline)
	gfx.cmd_push_constants(
		cmd,
		GPUDDGIUpdatePush{volume = volume.config_buffer.ptr, radiance = volume.radiance_buffer.ptr, irradiance = volume.gpu.irradiance},
	)
	vk.CmdDispatch(cmd, num_probes, 1, 1)
	gfx.image_barrier(
		cmd,
		{
			image      = &volume.irradiance,
			src_access = .ComputeShaderWrite,
			dst_access = .AllShaderRead,
		},
	)

	// Pass C: depth update (Chebyshev moments). pc.irradiance bound to the DEPTH atlas.
	gfx.cmd_bind_pipeline(cmd, game.render_state.ddgi_rp.depth_update_pipeline)
	gfx.cmd_push_constants(
		cmd,
		GPUDDGIUpdatePush{volume = volume.config_buffer.ptr, radiance = volume.radiance_buffer.ptr, irradiance = volume.gpu.depth},
	)
	vk.CmdDispatch(cmd, num_probes, 1, 1)
	gfx.image_barrier(
		cmd,
		{
			image      = &volume.depth,
			src_access = .ComputeShaderWrite,
			dst_access = .ComputeShaderRead,
		},
	)

	// Pass C2: depth border copy.
	gfx.cmd_bind_pipeline(cmd, game.render_state.ddgi_rp.depth_border_pipeline)
	gfx.cmd_push_constants(
		cmd,
		GPUDDGIUpdatePush{volume = volume.config_buffer.ptr, radiance = volume.radiance_buffer.ptr, irradiance = volume.gpu.depth},
	)
	vk.CmdDispatch(cmd, num_probes, 1, 1)
	gfx.image_barrier(
		cmd,
		{
			image      = &volume.depth,
			src_access = .ComputeShaderWrite,
			dst_access = .AllShaderRead,
		},
	)

	// Pass D: probe relocation (offset atlas, 1 thread/probe). Reads the same radiance.
	gfx.cmd_bind_pipeline(cmd, game.render_state.ddgi_rp.relocate_pipeline)
	gfx.cmd_push_constants(
		cmd,
		GPUDDGIUpdatePush{volume = volume.config_buffer.ptr, radiance = volume.radiance_buffer.ptr, irradiance = volume.gpu.offset},
	)
	vk.CmdDispatch(cmd, (num_probes + 63) / 64, 1, 1)
	gfx.image_barrier(
		cmd,
		{
			image      = &volume.offset,
			src_access = .ComputeShaderWrite,
			dst_access = .AllShaderRead,
		},
	)
}

ddgi_debug_atlas_pass :: proc(cmd: vk.CommandBuffer, volume: ^DDGI_Volume_Resources) {
	gfx.cmd_bind_pipeline(cmd, game.render_state.ddgi_rp.debug_pipeline)
	gfx.cmd_push_constants(
		cmd,
		GPUDDGIDebugAtlasPush{volume = volume.config_buffer.ptr, out_image = game.render_state.temp_resources.resolved_image_id},
	)
	vk.CmdDispatch(cmd, u32(gfx.r_ctx.draw_extent.width + 15) / 16, u32(gfx.r_ctx.draw_extent.height + 15) / 16, 1)
}
