package renderer

import vk "vendor:vulkan"
import vma "deps:odin-vma"

util_transition_image :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	current_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
) {
	image_barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
	}

	image_barrier.pNext = nil

	image_barrier.srcStageMask = {.ALL_COMMANDS}
	image_barrier.srcAccessMask = {.MEMORY_WRITE}
	image_barrier.dstStageMask = {.ALL_COMMANDS}
	image_barrier.dstAccessMask = {.MEMORY_WRITE, .MEMORY_READ}

	image_barrier.oldLayout = current_layout
	image_barrier.newLayout = new_layout

	aspect_mask: vk.ImageAspectFlags = (new_layout == .DEPTH_ATTACHMENT_OPTIMAL || new_layout == .DEPTH_READ_ONLY_OPTIMAL) ? {.DEPTH} : {.COLOR}
	image_barrier.subresourceRange = init_image_subresource_range(aspect_mask)
	image_barrier.image = image

	dep_info := vk.DependencyInfo{}
	dep_info.sType = .DEPENDENCY_INFO
	dep_info.pNext = nil

	dep_info.imageMemoryBarrierCount = 1
	dep_info.pImageMemoryBarriers = &image_barrier

	vk.CmdPipelineBarrier2(cmd, &dep_info)
}

util_copy_image_to_image :: proc(
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
