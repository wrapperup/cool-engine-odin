package renderer

import "core:c"
import "core:fmt"
import "core:mem"

import ktx "deps:odin-libktx"
import vma "deps:odin-vma"

import vk "vendor:vulkan"

load_image_from_file :: proc(engine: ^VulkanEngine) -> AllocatedImage {
	ktx_texture: ^ktx.Texture2
	ktx_result := ktx.Texture2_CreateFromNamedFile("assets/test.ktx", {.TEXTURE_CREATE_LOAD_IMAGE_DATA}, &ktx_texture)

	assert(ktx_result == .SUCCESS, "Failed to load image.")

	ktx_image_data := ktx.Texture_GetData(ktx_texture)
	ktx_image_data_size := ktx.Texture_GetImageSize(ktx_texture, 0)
	ktx_image_format := ktx.Texture_GetVkFormat(ktx_texture)

	extent := vk.Extent3D{ktx_texture.baseWidth, ktx_texture.baseHeight, 1}

	allocated_image := AllocatedImage {
		extent = extent,
		format = ktx_image_format,
	}

	img_alloc_info := vma.AllocationCreateInfo {
		usage         = .GPU_ONLY,
		requiredFlags = {.DEVICE_LOCAL},
	}

	img_create_info := init_image_create_info(allocated_image.format, {.SAMPLED, .TRANSFER_DST}, extent)

	//allocate and create the image
	vk_check(
		vma.CreateImage(
			engine.allocator,
			&img_create_info,
			&img_alloc_info,
			&allocated_image.image,
			&allocated_image.allocation,
			nil,
		),
	)

	image_view_info := init_imageview_create_info(allocated_image.format, allocated_image.image, {.COLOR})

	vk_check(vk.CreateImageView(engine.device, &image_view_info, nil, &allocated_image.image_view))

	push_deletion_queue(&engine.main_deletion_queue, allocated_image.image_view)
	push_deletion_queue(&engine.main_deletion_queue, allocated_image.image, allocated_image.allocation)

	// Next, upload image data to vk Image
	staging := create_buffer(engine, vk.DeviceSize(ktx_image_data_size), {.TRANSFER_SRC}, .CPU_ONLY)
	data := staging.info.pMappedData

	mem.copy(data, ktx_image_data, int(ktx_image_data_size))

	if cmd, ok := immediate_submit(engine); ok {
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

	destroy_buffer(engine, &staging)

	return allocated_image
}
