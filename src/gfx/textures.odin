package gfx

import "core:c"
import "core:fmt"
import "core:math"
import "core:mem"

import ktx "deps:odin-libktx"
import vma "deps:odin-vma"

import vk "vendor:vulkan"

load_image_from_file :: proc(
	filename: cstring,
	image_type: vk.ImageType = .D2,
	image_view_type: vk.ImageViewType = .D2,
) -> AllocatedImage {
	ktx_texture: ^ktx.Texture2
	ktx_result := ktx.Texture2_CreateFromNamedFile(filename, {.TEXTURE_CREATE_LOAD_IMAGE_DATA}, &ktx_texture)

	assert(ktx_result == .SUCCESS, "Failed to load image.")

	num_faces := ktx_texture.numFaces // Faces (cubemap)
	num_levels := ktx_texture.numLevels // Mip levels
	num_layers := ktx_texture.numLayers // Array levels

	is_array := ktx_texture.isArray
	is_cubemap := ktx_texture.isCubemap

	// Don't support cubemap arrays... if that's even a thing.
	assert(!(is_cubemap && is_array))

	// Assign cubemap faces instead.
	if is_cubemap do num_layers = num_faces

	size := ktx.Texture_GetDataSize(ktx_texture)
	data := ktx.Texture_GetData(ktx_texture)
	format := ktx.Texture_GetVkFormat(ktx_texture)

	extent := vk.Extent3D{ktx_texture.baseWidth, ktx_texture.baseHeight, ktx_texture.baseDepth}

	image := create_image(format, extent, {.SAMPLED, .TRANSFER_DST}, image_type = image_type, array_layers = num_layers, flags = is_cubemap ? {.CUBE_COMPATIBLE} : {})
	create_image_view(&image, {.COLOR}, image_view_type = image_view_type)

	// Next, upload image data to vk Image
	staging := create_buffer(vk.DeviceSize(size), {.TRANSFER_SRC}, .CPU_ONLY)
	mapped_data := staging.info.pMappedData

	mem.copy(mapped_data, data, int(size))

	copy_regions: [dynamic]vk.BufferImageCopy

	for i in 0 ..< num_layers {
		for level in 0 ..< num_levels {
			offset: uint
			if is_cubemap {
				ret := ktx.Texture_GetImageOffset(ktx_texture, level, 0, i, &offset)
				assert(ret == .SUCCESS)
			} else {
				ret := ktx.Texture_GetImageOffset(ktx_texture, level, i, 0, &offset)
				assert(ret == .SUCCESS)
			}

			copy_region := vk.BufferImageCopy{}
			copy_region.imageSubresource.aspectMask = {.COLOR}
			copy_region.imageSubresource.mipLevel = level
			copy_region.imageSubresource.baseArrayLayer = i
			copy_region.imageSubresource.layerCount = 1
			copy_region.imageExtent.width = ktx_texture.baseWidth >> level
			copy_region.imageExtent.height = ktx_texture.baseHeight >> level
			copy_region.imageExtent.depth = ktx_texture.baseDepth >> level
			copy_region.bufferOffset = vk.DeviceSize(offset)

			append(&copy_regions, copy_region)
		}
	}

	if cmd, ok := immediate_submit(); ok {
		transition_image(cmd, image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
		vk.CmdCopyBufferToImage(cmd, staging.buffer, image.image, .TRANSFER_DST_OPTIMAL, u32(len(copy_regions)), raw_data(copy_regions))
		transition_image(cmd, image.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
	}

	destroy_buffer(&staging)

	push_deletion_queue(&r_ctx.main_deletion_queue, image.image_view)
	push_deletion_queue(&r_ctx.main_deletion_queue, image.image, image.allocation)

	return image
}

load_image_from_bytes :: proc(
	bytes: []u8,
	extent: vk.Extent3D,
	image_format: vk.Format,
	image_type: vk.ImageType = .D2,
	image_view_type: vk.ImageViewType = .D2,
) -> AllocatedImage {
	image := create_image(image_format, extent, {.SAMPLED, .TRANSFER_DST}, image_type = image_type)
	create_image_view(&image, {.COLOR}, image_view_type = image_view_type)

	push_deletion_queue(&r_ctx.main_deletion_queue, image.image_view)
	push_deletion_queue(&r_ctx.main_deletion_queue, image.image, image.allocation)

	// Next, upload image data to vk Image
	staging := create_buffer(vk.DeviceSize(len(bytes)), {.TRANSFER_SRC}, .CPU_ONLY)
	data := staging.info.pMappedData

	mem.copy(data, raw_data(bytes), len(bytes))

	if cmd, ok := immediate_submit(); ok {
		transition_image(cmd, image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

		copy_region := vk.BufferImageCopy {
			bufferOffset = 0,
			bufferRowLength = 0,
			bufferImageHeight = 0,
			imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
			imageExtent = extent,
		}

		vk.CmdCopyBufferToImage(cmd, staging.buffer, image.image, .TRANSFER_DST_OPTIMAL, 1, &copy_region)

		transition_image(cmd, image.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
	}

	destroy_buffer(&staging)

	return image
}
