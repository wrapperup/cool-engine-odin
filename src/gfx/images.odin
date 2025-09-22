package gfx

import vma "deps:odin-vma"
import vk "vendor:vulkan"

GPUImage :: struct {
	image:          vk.Image,
	image_view:     vk.ImageView,
	allocation:     vma.Allocation,
	extent:         vk.Extent3D,
	format:         vk.Format,
	mip_levels:     u32,
	array_layers:   u32,
	current_layout: vk.ImageLayout,
	usage:          vk.ImageUsageFlags,
}

// This allocates on the GPU, make sure to call `destroy_image` or add to the deletion queue when you are finished with the image.
create_gpu_image :: proc(
	format: vk.Format,
	extent: vk.Extent3D,
	image_usage_flags: vk.ImageUsageFlags,
	mip_levels: u32 = 1,
	array_layers: u32 = 1,
	image_type: vk.ImageType = .D2,
	msaa_samples: vk.SampleCountFlag = ._1,
	tiling: vk.ImageTiling = .OPTIMAL,
	flags: vk.ImageCreateFlags = {},
	alloc_flags: vma.AllocationCreateFlags = {},
	usage: vma.MemoryUsage = .GPU_ONLY,
) -> GPUImage {
	img_alloc_info := vma.AllocationCreateInfo {
		usage         = usage,
		requiredFlags = {.DEVICE_LOCAL},
		flags         = alloc_flags,
	}

	img_info := init_image_create_info(
		format,
		image_usage_flags,
		extent,
		mip_levels,
		array_layers,
		msaa_samples,
		image_type,
		flags,
		tiling,
	)

	new_image := GPUImage {
		extent       = extent,
		format       = format,
		mip_levels   = mip_levels,
		array_layers = array_layers,
		usage        = image_usage_flags,
	}

	vk_check(vma.CreateImage(r_ctx.allocator, &img_info, &img_alloc_info, &new_image.image, &new_image.allocation, nil))

	return new_image
}

create_gpu_image_view :: proc(
	image: ^GPUImage,
	aspect_flags: vk.ImageAspectFlags,
	view_type: vk.ImageViewType = .D2,
	base_mip_level: u32 = 0,
	base_array_layer: u32 = 0,
) {
	image.image_view = create_image_view(
		image.image,
		image.format,
		aspect_flags,
		view_type,
		base_mip_level,
		image.mip_levels,
		base_array_layer,
		image.array_layers,
	)
}

create_image_view :: proc(
	image: vk.Image,
	format: vk.Format,
	aspect_flags: vk.ImageAspectFlags,
	view_type: vk.ImageViewType = .D2,
	#any_int base_mip_level: u32 = 0,
	#any_int mip_levels: u32 = 1,
	#any_int base_array_layer: u32 = 0,
	#any_int array_layers: u32 = 1,
) -> vk.ImageView {
	info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = view_type,
		image = image,
		format = format,
		subresourceRange = {
			baseMipLevel = base_mip_level,
			levelCount = mip_levels,
			baseArrayLayer = base_array_layer,
			layerCount = array_layers,
			aspectMask = aspect_flags,
		},
	}

	image_view: vk.ImageView
	vk_check(vk.CreateImageView(r_ctx.device, &info, nil, &image_view))

	return image_view
}

create_sampler :: proc(
	filter: vk.Filter,
	address_mode: vk.SamplerAddressMode,
	compare_op: vk.CompareOp = .NEVER,
	border_color: vk.BorderColor = .FLOAT_TRANSPARENT_BLACK,
	max_lod: f32 = 1.0,
	max_anisotropy: f32 = 1.0,
) -> vk.Sampler {
	sampler_create_info := vk.SamplerCreateInfo {
		sType            = .SAMPLER_CREATE_INFO,
		magFilter        = filter,
		minFilter        = filter,
		mipmapMode       = .LINEAR,
		addressModeU     = address_mode,
		addressModeV     = address_mode,
		addressModeW     = address_mode,
		mipLodBias       = 0.0,
		anisotropyEnable = max_anisotropy > 1.0 ? true : false,
		maxAnisotropy    = max_anisotropy,
		minLod           = 0.0,
		maxLod           = max_lod,
		borderColor      = border_color,
		compareOp        = compare_op,
		compareEnable    = compare_op != .NEVER,
	}

	sampler: vk.Sampler
	vk_check(vk.CreateSampler(r_ctx.device, &sampler_create_info, nil, &sampler))

	return sampler
}

transition_vk_image :: proc(cmd: vk.CommandBuffer, image: vk.Image, current_layout: vk.ImageLayout, new_layout: vk.ImageLayout) {
	image_barrier := vk.ImageMemoryBarrier2 {
		sType         = .IMAGE_MEMORY_BARRIER_2,
		pNext         = nil,
		srcStageMask  = {.ALL_COMMANDS},
		srcAccessMask = {.MEMORY_WRITE},
		dstStageMask  = {.ALL_COMMANDS},
		dstAccessMask = {.MEMORY_WRITE, .MEMORY_READ},
		oldLayout     = current_layout,
		newLayout     = new_layout,
	}

	aspect_mask: vk.ImageAspectFlags =
		(new_layout == .DEPTH_ATTACHMENT_OPTIMAL || new_layout == .DEPTH_READ_ONLY_OPTIMAL) ? {.DEPTH} : {.COLOR}

	image_barrier.subresourceRange = init_image_subresource_range(aspect_mask)
	image_barrier.image = image

	dep_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		pNext                   = nil,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &image_barrier,
	}

	vk.CmdPipelineBarrier2(cmd, &dep_info)
}

transition_image :: proc(cmd: vk.CommandBuffer, image: ^GPUImage, new_layout: vk.ImageLayout) -> bool {
	image_barrier := vk.ImageMemoryBarrier2 {
		sType         = .IMAGE_MEMORY_BARRIER_2,
		pNext         = nil,
		srcStageMask  = {.ALL_COMMANDS},
		srcAccessMask = {.MEMORY_WRITE},
		dstStageMask  = {.ALL_COMMANDS},
		dstAccessMask = {.MEMORY_WRITE, .MEMORY_READ},
		oldLayout     = image.current_layout,
		newLayout     = new_layout,
	}

	aspect_mask: vk.ImageAspectFlags =
		(new_layout == .DEPTH_ATTACHMENT_OPTIMAL || new_layout == .DEPTH_READ_ONLY_OPTIMAL) ? {.DEPTH} : {.COLOR}

	image_barrier.subresourceRange = init_image_subresource_range(aspect_mask)
	image_barrier.image = image.image

	dep_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		pNext                   = nil,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &image_barrier,
	}

	vk.CmdPipelineBarrier2(cmd, &dep_info)
	image.current_layout = new_layout

	return true
}

copy_image_to_image :: proc(cmd: vk.CommandBuffer, source: vk.Image, destination: vk.Image, src_size: vk.Extent2D, dst_size: vk.Extent2D) {
	blit_region := vk.ImageBlit2 {
		sType = .IMAGE_BLIT_2,
		pNext = nil,
	}

	blit_region.srcOffsets[1].x = i32(src_size.width)
	blit_region.srcOffsets[1].y = i32(src_size.height)
	blit_region.srcOffsets[1].z = 1

	blit_region.dstOffsets[1].x = i32(dst_size.width)
	blit_region.dstOffsets[1].y = i32(dst_size.height)
	blit_region.dstOffsets[1].z = 1

	blit_region.srcSubresource.aspectMask = {.COLOR}
	blit_region.srcSubresource.baseArrayLayer = 0
	blit_region.srcSubresource.layerCount = 1
	blit_region.srcSubresource.mipLevel = 0

	blit_region.dstSubresource.aspectMask = {.COLOR}
	blit_region.dstSubresource.baseArrayLayer = 0
	blit_region.dstSubresource.layerCount = 1
	blit_region.dstSubresource.mipLevel = 0

	blit_info := vk.BlitImageInfo2 {
		sType          = .BLIT_IMAGE_INFO_2,
		pNext          = nil,
		dstImage       = destination,
		dstImageLayout = .TRANSFER_DST_OPTIMAL,
		srcImage       = source,
		srcImageLayout = .TRANSFER_SRC_OPTIMAL,
		filter         = .LINEAR,
		regionCount    = 1,
		pRegions       = &blit_region,
	}

	vk.CmdBlitImage2(cmd, &blit_info)
}

destroy_gpu_image :: proc(gpu_image: GPUImage) {
	vk.DestroyImageView(r_ctx.device, gpu_image.image_view, nil)
	vma.DestroyImage(r_ctx.allocator, gpu_image.image, gpu_image.allocation)
}
