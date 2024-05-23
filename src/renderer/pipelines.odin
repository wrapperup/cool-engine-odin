package renderer

import "core:fmt"
import "core:os"
import "core:slice"

import vk "vendor:vulkan"

PipelineBuilder :: struct {
	shader_stages:           [dynamic]vk.PipelineShaderStageCreateInfo,
	input_assembly:          vk.PipelineInputAssemblyStateCreateInfo,
	rasterizer:              vk.PipelineRasterizationStateCreateInfo,
	color_blend_attachment:  vk.PipelineColorBlendAttachmentState,
	multisampling:           vk.PipelineMultisampleStateCreateInfo,
	pipeline_layout:         vk.PipelineLayout,
	depth_stencil:           vk.PipelineDepthStencilStateCreateInfo,
	render_info:             vk.PipelineRenderingCreateInfo,
	color_attachment_format: vk.Format,
}

// This allocates, be sure to call pb_delete.
pb_init :: proc() -> PipelineBuilder {
	pb: PipelineBuilder
	pb_clear(&pb)
	return pb
}

pb_clear :: proc(builder: ^PipelineBuilder) {
	builder.input_assembly = {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
	}
	builder.rasterizer = {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
	}
	builder.color_blend_attachment = {}
	builder.multisampling = {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
	}
	builder.pipeline_layout = {}
	builder.depth_stencil = {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
	}
	builder.render_info = {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
	}
	builder.color_attachment_format = {}

	clear(&builder.shader_stages)
}

pb_build_pipeline :: proc(builder: ^PipelineBuilder, device: vk.Device) -> vk.Pipeline {
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
	}
	viewport_state.viewportCount = 1
	viewport_state.scissorCount = 1

	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
	}
	color_blending.logicOpEnable = false
	color_blending.logicOp = .COPY
	color_blending.attachmentCount = 1
	color_blending.pAttachments = &builder.color_blend_attachment

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	pipelineInfo := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
	}
	pipelineInfo.pNext = &builder.render_info

	pipelineInfo.pStages = raw_data(builder.shader_stages)
	pipelineInfo.stageCount = u32(len(builder.shader_stages))

	pipelineInfo.pVertexInputState = &vertex_input_info
	pipelineInfo.pInputAssemblyState = &builder.input_assembly
	pipelineInfo.pViewportState = &viewport_state
	pipelineInfo.pRasterizationState = &builder.rasterizer
	pipelineInfo.pMultisampleState = &builder.multisampling
	pipelineInfo.pColorBlendState = &color_blending
	pipelineInfo.pDepthStencilState = &builder.depth_stencil
	pipelineInfo.layout = builder.pipeline_layout

	state := []vk.DynamicState{.VIEWPORT, .SCISSOR}

	dynamicInfo := vk.PipelineDynamicStateCreateInfo {
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
	}
	dynamicInfo.pDynamicStates = raw_data(state)
	dynamicInfo.dynamicStateCount = u32(len(state))

	pipelineInfo.pDynamicState = &dynamicInfo

	newPipeline: vk.Pipeline
	if vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &newPipeline) != .SUCCESS {
		fmt.eprintln("failed to create pipeline")
		return 0
	} else {
		return newPipeline
	}
}

pb_set_shaders :: proc(
	builder: ^PipelineBuilder,
	shader: vk.ShaderModule,
	vertex_entry: cstring = "vertex_main",
	fragment_entry: cstring = "fragment_main",
) {
	clear(&builder.shader_stages)
	append(&builder.shader_stages, init_pipeline_shader_stage_create_info({.VERTEX}, shader, vertex_entry))
	append(&builder.shader_stages, init_pipeline_shader_stage_create_info({.FRAGMENT}, shader, fragment_entry))
}

pb_set_input_topology :: proc(builder: ^PipelineBuilder, topology: vk.PrimitiveTopology) {
	builder.input_assembly.topology = topology
	builder.input_assembly.primitiveRestartEnable = false
}

pb_set_polygon_mode :: proc(builder: ^PipelineBuilder, mode: vk.PolygonMode) {
	builder.rasterizer.polygonMode = mode
	builder.rasterizer.lineWidth = 1.
}

pb_set_cull_mode :: proc(builder: ^PipelineBuilder, cull_mode: vk.CullModeFlags, front_face: vk.FrontFace) {
	builder.rasterizer.cullMode = cull_mode
	builder.rasterizer.frontFace = front_face
}

pb_set_multisampling_none :: proc(builder: ^PipelineBuilder) {
	builder.multisampling.sampleShadingEnable = false

	builder.multisampling.rasterizationSamples = {._1}
	builder.multisampling.minSampleShading = 1.0
	builder.multisampling.pSampleMask = nil

	builder.multisampling.alphaToCoverageEnable = false
	builder.multisampling.alphaToOneEnable = false
}

pb_set_multisampling :: proc(builder: ^PipelineBuilder, samples: vk.SampleCountFlag) {
	builder.multisampling.sampleShadingEnable = false

	builder.multisampling.rasterizationSamples = {samples}
	builder.multisampling.minSampleShading = 1.0
	builder.multisampling.pSampleMask = nil

	builder.multisampling.alphaToCoverageEnable = false
	builder.multisampling.alphaToOneEnable = false
}

pb_disable_blending :: proc(builder: ^PipelineBuilder) {
	builder.color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
	builder.color_blend_attachment.blendEnable = false
}

pb_set_color_attachment_format :: proc(builder: ^PipelineBuilder, format: vk.Format) {
	builder.color_attachment_format = format

	builder.render_info.colorAttachmentCount = 1
	builder.render_info.pColorAttachmentFormats = &builder.color_attachment_format
}

pb_disable_color_attachment :: proc(builder: ^PipelineBuilder) {
	builder.color_attachment_format = .UNDEFINED

	builder.render_info.colorAttachmentCount = 0
	builder.render_info.pColorAttachmentFormats = nil
}

pb_set_depth_format :: proc(builder: ^PipelineBuilder, format: vk.Format) {
	builder.render_info.depthAttachmentFormat = format
}

pb_disable_depthtest :: proc(builder: ^PipelineBuilder) {
	builder.depth_stencil.depthTestEnable = false
	builder.depth_stencil.depthWriteEnable = false
	builder.depth_stencil.depthCompareOp = .NEVER
	builder.depth_stencil.depthBoundsTestEnable = false
	builder.depth_stencil.stencilTestEnable = false
	builder.depth_stencil.front = {}
	builder.depth_stencil.back = {}
	builder.depth_stencil.minDepthBounds = 0.0
	builder.depth_stencil.maxDepthBounds = 1.0
}

pb_enable_depthtest :: proc(builder: ^PipelineBuilder, depth_write_enable: b32, op: vk.CompareOp) {
	builder.depth_stencil.depthTestEnable = true
	builder.depth_stencil.depthWriteEnable = depth_write_enable
	builder.depth_stencil.depthCompareOp = op
	builder.depth_stencil.depthBoundsTestEnable = false
	builder.depth_stencil.stencilTestEnable = false
	builder.depth_stencil.front = {}
	builder.depth_stencil.back = {}
	builder.depth_stencil.minDepthBounds = 0.0
	builder.depth_stencil.maxDepthBounds = 1.0
}


pb_delete :: proc(builder: PipelineBuilder) {
	delete(builder.shader_stages)
}

// ====================================================================

util_load_shader_module :: proc(file_name: string, device: vk.Device) -> (vk.ShaderModule, bool) {
	buffer, ok := os.read_entire_file(file_name)

	if !ok {
		return 0, false
	}

	defer delete(buffer)

	info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(buffer), // codeSize needs to be in bytes
		pCode    = raw_data(slice.reinterpret([]u32, buffer)), // code needs to be in 32bit words
	}

	module: vk.ShaderModule
	if vk.CreateShaderModule(device, &info, nil, &module) != .SUCCESS {
		return 0, false
	}

	return module, true
}
