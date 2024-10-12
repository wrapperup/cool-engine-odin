package gfx

import "core:c"
import "core:fmt"
import "core:mem"

import ktx "deps:odin-libktx"
import vma "deps:odin-vma"

import vk "vendor:vulkan"

load_image_from_file :: proc(filename: cstring) -> AllocatedImage {
	ktx_texture: ^ktx.Texture2
	ktx_result := ktx.Texture2_CreateFromNamedFile(filename, {.TEXTURE_CREATE_LOAD_IMAGE_DATA}, &ktx_texture)

	assert(ktx_result == .SUCCESS, "Failed to load image.")

	offset: uint
	result := ktx.Texture_GetImageOffset(ktx_texture, 0, 0, 0, &offset)
	assert(result == .SUCCESS)

	ktx_image_data := cast([^]u8)(&ktx.Texture_GetData(ktx_texture)[offset])
	fmt.println(ktx.Texture_GetData(ktx_texture))
	fmt.println(ktx_image_data)
	ktx_image_data_size := ktx.Texture_GetImageSize(ktx_texture, 0) * uint(ktx_texture.baseDepth)
	ktx_image_format := ktx.Texture_GetVkFormat(ktx_texture)

	fmt.println("offset: ", offset)

	fmt.println(ktx_image_format)
	fmt.println(ktx_image_data_size)
	fmt.println(ktx_texture.numLevels)
	fmt.println(ktx_texture.isArray)

	extent := vk.Extent3D{ktx_texture.baseWidth, ktx_texture.baseHeight, ktx_texture.baseDepth}

	fmt.println(extent)

	allocated_image := AllocatedImage {
		extent = extent,
		format = ktx_image_format,
	}

	img_alloc_info := vma.AllocationCreateInfo {
		usage         = .GPU_ONLY,
		requiredFlags = {.DEVICE_LOCAL},
	}

	img_create_info := init_image_create_info(allocated_image.format, {.SAMPLED, .TRANSFER_DST}, extent, image_type = .D3)

	//allocate and create the image
	vk_check(vma.CreateImage(r_ctx.allocator, &img_create_info, &img_alloc_info, &allocated_image.image, &allocated_image.allocation, nil))

	image_view_info := init_imageview_create_info(allocated_image.format, allocated_image.image, {.COLOR}, .D3)

	vk_check(vk.CreateImageView(r_ctx.device, &image_view_info, nil, &allocated_image.image_view))

	push_deletion_queue(&r_ctx.main_deletion_queue, allocated_image.image_view)
	push_deletion_queue(&r_ctx.main_deletion_queue, allocated_image.image, allocated_image.allocation)

	// Next, upload image data to vk Image
	staging := create_buffer(vk.DeviceSize(ktx_image_data_size), {.TRANSFER_SRC}, .CPU_ONLY)
	data := staging.info.pMappedData

	mem.copy(data, ktx_image_data, int(ktx_image_data_size))

	if cmd, ok := immediate_submit(); ok {
		transition_image(cmd, allocated_image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

		copy_region := vk.BufferImageCopy {
			bufferOffset = 0,
			bufferRowLength = 0,
			bufferImageHeight = 0,
			imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
			imageExtent = extent,
		}

		vk.CmdCopyBufferToImage(cmd, staging.buffer, allocated_image.image, .TRANSFER_DST_OPTIMAL, 1, &copy_region)

		transition_image(cmd, allocated_image.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
	}

	destroy_buffer(&staging)

	return allocated_image
}
