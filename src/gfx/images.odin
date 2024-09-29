package gfx

import vma "deps:odin-vma"
import vk "vendor:vulkan"

import "core:fmt"

AllocatedImage :: struct {
	image:      vk.Image,
	image_view: vk.ImageView,
	allocation: vma.Allocation,
	extent:     vk.Extent3D,
	format:     vk.Format,
}

// This allocates on the GPU, make sure to call `destroy_image` or add to the deletion queue when you are finished with the image.
create_image :: proc(
	engine: ^Renderer,
	format: vk.Format,
	extent: vk.Extent3D,
	image_usage_flags: vk.ImageUsageFlags,
	sample_count: vk.SampleCountFlag = ._1,
	alloc_flags: vma.AllocationCreateFlags = {},
) -> AllocatedImage {
	img_alloc_info := vma.AllocationCreateInfo {
		usage         = .GPU_ONLY,
		requiredFlags = {.DEVICE_LOCAL},
		flags         = alloc_flags,
	}

	img_info := init_image_create_info(format, image_usage_flags, extent, ._1)

	new_image := AllocatedImage {
		extent = extent,
		format = format,
	}

	vk_check(
		vma.CreateImage(engine.allocator, &img_info, &img_alloc_info, &new_image.image, &new_image.allocation, nil),
	)

	return new_image
}

create_image_view :: proc(device: vk.Device, image: ^AllocatedImage, aspect_flags: vk.ImageAspectFlags) {
	dview_info := init_imageview_create_info(image.format, image.image, aspect_flags)
	vk_check(vk.CreateImageView(device, &dview_info, nil, &image.image_view))
}

create_sampler :: proc(
	device: vk.Device,
	filter: vk.Filter,
	address_mode: vk.SamplerAddressMode,
	compare_op: vk.CompareOp = .NEVER,
	border_color: vk.BorderColor = .FLOAT_TRANSPARENT_BLACK,
) -> vk.Sampler {
	sampler_create_info := init_sampler_create_info(filter, address_mode, compare_op, border_color)

	sampler: vk.Sampler
	vk_check(vk.CreateSampler(device, &sampler_create_info, nil, &sampler))

	return sampler
}

transition_image_allocated_image :: proc(
	cmd: vk.CommandBuffer,
	allocated_image: AllocatedImage,
	current_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
) {
	transition_image_vkimage(cmd, allocated_image.image, current_layout, new_layout)
}

transition_image_vkimage :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	current_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
) {
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

transition_image :: proc {
	transition_image_allocated_image,
	transition_image_vkimage,
}

copy_image_to_image :: proc(
	cmd: vk.CommandBuffer,
	source: vk.Image,
	destination: vk.Image,
	src_size: vk.Extent2D,
	dst_size: vk.Extent2D,
) {
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
		sType = .BLIT_IMAGE_INFO_2,
		pNext = nil,
	}
	blit_info.dstImage = destination
	blit_info.dstImageLayout = .TRANSFER_DST_OPTIMAL
	blit_info.srcImage = source
	blit_info.srcImageLayout = .TRANSFER_SRC_OPTIMAL
	blit_info.filter = .LINEAR
	blit_info.regionCount = 1
	blit_info.pRegions = &blit_region

	vk.CmdBlitImage2(cmd, &blit_info)
}
