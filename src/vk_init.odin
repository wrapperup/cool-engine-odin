package main

import vk "vendor:vulkan"

init_command_pool_create_info :: proc(
	queue_family_index: u32,
	flags: vk.CommandPoolCreateFlags,
) -> vk.CommandPoolCreateInfo {
	info := vk.CommandPoolCreateInfo{}
	info.sType = .COMMAND_POOL_CREATE_INFO
	info.pNext = nil
	info.queueFamilyIndex = queue_family_index
	info.flags = flags

	return info
}

init_command_buffer_allocate_info :: proc(pool: vk.CommandPool, count: u32) -> vk.CommandBufferAllocateInfo {
	info := vk.CommandBufferAllocateInfo{}
	info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
	info.pNext = nil

	info.commandPool = pool
	info.commandBufferCount = count
	info.level = .PRIMARY
	return info
}

init_fence_create_info :: proc(flags: vk.FenceCreateFlags) -> vk.FenceCreateInfo {
	info := vk.FenceCreateInfo{}
	info.sType = .FENCE_CREATE_INFO
	info.pNext = nil

	info.flags = flags

	return info
}

init_semaphore_create_info :: proc(flags: vk.SemaphoreCreateFlags) -> vk.SemaphoreCreateInfo {
	info := vk.SemaphoreCreateInfo{}
	info.sType = .SEMAPHORE_CREATE_INFO
	info.pNext = nil
	info.flags = flags
	return info
}

init_command_buffer_begin_info :: proc(flags: vk.CommandBufferUsageFlags) -> vk.CommandBufferBeginInfo {
	info := vk.CommandBufferBeginInfo{}
	info.sType = .COMMAND_BUFFER_BEGIN_INFO
	info.pNext = nil

	info.pInheritanceInfo = nil
	info.flags = flags

	return info
}

init_image_subresource_range :: proc(aspect_mask: vk.ImageAspectFlags) -> vk.ImageSubresourceRange {
	sub_image := vk.ImageSubresourceRange{}
	sub_image.aspectMask = aspect_mask
	sub_image.baseMipLevel = 0
	sub_image.levelCount = vk.REMAINING_MIP_LEVELS
	sub_image.baseArrayLayer = 0
	sub_image.layerCount = vk.REMAINING_ARRAY_LAYERS

	return sub_image
}

init_semaphore_submit_info :: proc(
	stage_mask: vk.PipelineStageFlags2,
	semaphore: vk.Semaphore,
) -> vk.SemaphoreSubmitInfo {
	info := vk.SemaphoreSubmitInfo{}
	info.sType = .SEMAPHORE_SUBMIT_INFO
	info.pNext = nil
	info.semaphore = semaphore
	info.stageMask = stage_mask
	info.deviceIndex = 0
	info.value = 1

	return info
}

init_command_buffer_submit_info :: proc(cmd: vk.CommandBuffer) -> vk.CommandBufferSubmitInfo {
	info := vk.CommandBufferSubmitInfo{}
	info.sType = .COMMAND_BUFFER_SUBMIT_INFO
	info.pNext = nil
	info.commandBuffer = cmd
	info.deviceMask = 0

	return info
}

init_submit_info :: proc(
	cmd: ^vk.CommandBufferSubmitInfo,
	signal_semaphore_info: ^vk.SemaphoreSubmitInfo,
	wait_semaphore_info: ^vk.SemaphoreSubmitInfo,
) -> vk.SubmitInfo2 {
	info := vk.SubmitInfo2{}
	info.sType = .SUBMIT_INFO_2
	info.pNext = nil

	info.waitSemaphoreInfoCount = wait_semaphore_info == nil ? 0 : 1
	info.pWaitSemaphoreInfos = wait_semaphore_info

	info.signalSemaphoreInfoCount = signal_semaphore_info == nil ? 0 : 1
	info.pSignalSemaphoreInfos = signal_semaphore_info

	info.commandBufferInfoCount = 1
	info.pCommandBufferInfos = cmd

	return info
}

init_image_create_info :: proc(
	format: vk.Format,
	usage_flags: vk.ImageUsageFlags,
	extent: vk.Extent3D,
	msaa_samples: vk.SampleCountFlag = ._1,
) -> vk.ImageCreateInfo {
	info := vk.ImageCreateInfo {
		sType       = .IMAGE_CREATE_INFO,
		imageType   = .D2,
		format      = format,
		extent      = extent,
		mipLevels   = 1,
		arrayLayers = 1,
		samples     = {msaa_samples},
		tiling      = .OPTIMAL,
		usage       = usage_flags,
	}

	return info
}

init_imageview_create_info :: proc(
	format: vk.Format,
	image: vk.Image,
	aspect_flags: vk.ImageAspectFlags,
) -> vk.ImageViewCreateInfo {
	info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		image = image,
		format = format,
		subresourceRange =  {
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
			aspectMask = aspect_flags,
		},
	}

	return info
}

init_attachment_info :: proc(
	view: vk.ImageView,
	clear: ^vk.ClearValue,
	layout: vk.ImageLayout,
) -> vk.RenderingAttachmentInfo {
	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = view,
		imageLayout = layout,
		loadOp      = clear != nil ? .CLEAR : .LOAD,
		storeOp     = .STORE,
		clearValue  = clear != nil ? clear^ : {},
	}

	return color_attachment
}

init_depth_attachment_info :: proc(
	view: vk.ImageView,
	layout: vk.ImageLayout,
) -> vk.RenderingAttachmentInfo {
	depth_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
	}

	depth_attachment.imageView = view
	depth_attachment.imageLayout = layout
	depth_attachment.loadOp = .CLEAR
	depth_attachment.storeOp = .STORE
	depth_attachment.clearValue.depthStencil.depth = 1.0

	return depth_attachment
}

init_rendering_info :: proc(
	area: vk.Extent2D,
	color_attachment: ^vk.RenderingAttachmentInfo,
	depth_attachment: ^vk.RenderingAttachmentInfo,
) -> vk.RenderingInfo {
	info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		layerCount = 1,
		renderArea = {extent = area},
		pDepthAttachment = depth_attachment,
		pColorAttachments = color_attachment,
		colorAttachmentCount = 1,
	}

	return info
}

init_pipeline_layout_create_info :: proc() -> vk.PipelineLayoutCreateInfo {
	info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = nil,
		flags                  = {},
		setLayoutCount         = 0,
		pSetLayouts            = nil,
		pushConstantRangeCount = 0,
		pPushConstantRanges    = nil,
	}

	return info
}

init_pipeline_shader_stage_create_info :: proc(
	stage: vk.ShaderStageFlags,
	shader_module: vk.ShaderModule,
	entry: cstring = "main",
) -> vk.PipelineShaderStageCreateInfo {
	info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = stage,
		module = shader_module,
		pName  = entry,
	}
	return info
}
