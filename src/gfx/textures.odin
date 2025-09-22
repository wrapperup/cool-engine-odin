package gfx

import "core:log"
import "core:mem"

import ktx "deps:odin-libktx"

import vk "vendor:vulkan"

load_image_from_file :: proc(
	filename: cstring,
	image_type: vk.ImageType = .D2,
	image_view_type: vk.ImageViewType = .D2,
	out_width: ^u32 = nil,
	out_height: ^u32 = nil,
	out_depth: ^u32 = nil,
) -> GPUImage {
	ktx_texture: ^ktx.Texture2
	ktx_result := ktx.Texture2_CreateFromNamedFile(filename, {.TEXTURE_CREATE_LOAD_IMAGE_DATA}, &ktx_texture)

    assert(ktx_result == .SUCCESS, "Failed to load image.")

    return load_image_from_ktx_texture(ktx_texture, image_type, image_view_type, out_width, out_height, out_depth)
}

load_image_from_memory :: proc(
	mem: []u8,
	image_type: vk.ImageType = .D2,
	image_view_type: vk.ImageViewType = .D2,
	out_width: ^u32 = nil,
	out_height: ^u32 = nil,
	out_depth: ^u32 = nil,
) -> GPUImage {
	ktx_texture: ^ktx.Texture2
	ktx_result := ktx.Texture2_CreateFromMemory(raw_data(mem), len(mem), {.TEXTURE_CREATE_LOAD_IMAGE_DATA}, &ktx_texture)

    assert(ktx_result == .SUCCESS, "Failed to load image.")

    return load_image_from_ktx_texture(ktx_texture, image_type, image_view_type, out_width, out_height, out_depth)
}

load_image_from_ktx_texture :: proc(
	ktx_texture: ^ktx.Texture2,
	image_type: vk.ImageType = .D2,
	image_view_type: vk.ImageViewType = .D2,
	out_width: ^u32 = nil,
	out_height: ^u32 = nil,
	out_depth: ^u32 = nil,
) -> GPUImage {
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

	log.info("format:", format)

	extent := vk.Extent3D{ktx_texture.baseWidth, ktx_texture.baseHeight, ktx_texture.baseDepth}

	image := create_gpu_image(
		format,
		extent,
		{.SAMPLED, .TRANSFER_DST},
		image_type = image_type,
		mip_levels = num_levels,
		array_layers = num_layers,
		flags = is_cubemap ? {.CUBE_COMPATIBLE} : {},
	)
	create_gpu_image_view(&image, {.COLOR}, image_view_type, 0, 0)

	// Next, upload image data to vk Image
	staging := create_buffer(u8, vk.DeviceSize(size), {.TRANSFER_SRC}, .CPU_ONLY)
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
			copy_region.imageExtent.width = max(ktx_texture.baseWidth >> level, 1)
			copy_region.imageExtent.height = max(ktx_texture.baseHeight >> level, 1)
			copy_region.imageExtent.depth = max(ktx_texture.baseDepth >> level, 1)
			copy_region.bufferOffset = vk.DeviceSize(offset)

			append(&copy_regions, copy_region)
		}
	}

	if cmd, ok := immediate_submit(); ok {
		transition_image(cmd, &image, .TRANSFER_DST_OPTIMAL)
		vk.CmdCopyBufferToImage(cmd, staging.buffer, image.image, .TRANSFER_DST_OPTIMAL, u32(len(copy_regions)), raw_data(copy_regions))
		transition_image(cmd, &image, .SHADER_READ_ONLY_OPTIMAL)
	}

	destroy_buffer(&staging)

	defer_destroy(&r_ctx.global_arena, image.image_view)
	defer_destroy(&r_ctx.global_arena, image.image, image.allocation)

	if out_width != nil {
		out_width^ = ktx_texture.baseWidth
	}
	if out_height != nil {
		out_height^ = ktx_texture.baseHeight
	}
	if out_depth != nil {
		out_depth^ = ktx_texture.baseDepth
	}

	return image
}

// Uploads the data via a staging buffer. This is useful if your buffer is GPU only.
staging_write_image :: proc(gpu_image: ^GPUImage, in_data: ^$T, offset: vk.DeviceSize = 0, loc := #caller_location) {
	assert(gpu_image.image_view != 0, "GPUImage is missing a valid image view.")

	size := size_of(T)
	gpu_size := gpu_image.extent.width * gpu_image.extent.height * gpu_image.extent.depth * size_of(T) // TODO: Validate this.
	assert(gpu_size >= (u32(size) + u32(offset)), "The size of the data and offset is larger than the buffer", loc)

	staging := create_buffer(u8, vk.DeviceSize(size_of(T)), {.TRANSFER_SRC}, .CPU_ONLY)
	write_buffer(&staging, in_data)

	if cmd, ok := immediate_submit(); ok {
		transition_image(cmd, gpu_image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

		copy_region := vk.BufferImageCopy {
			bufferOffset = 0,
			bufferRowLength = 0,
			bufferImageHeight = 0,
			imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
			imageExtent = extent,
		}

		vk.CmdCopyBufferToImage(cmd, staging.buffer, gpu_image.image, .TRANSFER_DST_OPTIMAL, 1, &copy_region)

		transition_image(cmd, gpu_image.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
	}

	destroy_buffer(&staging)
}

// Uploads the data via a staging buffer. This is useful if your buffer is GPU only.
staging_write_image_slice :: proc(gpu_image: ^GPUImage, in_data: []$T, offset: vk.DeviceSize = 0, loc := #caller_location) {
	assert(gpu_image.image_view != 0, "GPUImage is missing a valid image view.")

	size := size_of(T) * len(in_data)
	gpu_size := gpu_image.extent.width * gpu_image.extent.height * gpu_image.extent.depth * size_of(T) // TODO: Validate this.
	assert(gpu_size >= (u32(size) + u32(offset)), "The size of the data and offset is larger than the buffer", loc)

	staging := create_buffer(u8, size, {.TRANSFER_SRC}, .CPU_ONLY)
	write_buffer_slice(&staging, in_data)

	if cmd, ok := immediate_submit(); ok {
		transition_image(cmd, gpu_image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

		copy_region := vk.BufferImageCopy {
			bufferOffset = 0,
			bufferRowLength = 0,
			bufferImageHeight = 0,
			imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
			imageExtent = gpu_image.extent,
		}

		vk.CmdCopyBufferToImage(cmd, staging.buffer, gpu_image.image, .TRANSFER_DST_OPTIMAL, 1, &copy_region)

		transition_image(cmd, gpu_image.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
	}

	destroy_buffer(&staging)
}

write_buffer_to_ktx_file :: proc(
	filename: cstring,
	buffer: ^GPUBuffer,
	extent: vk.Extent3D,
	format: vk.Format,
	format_size: u32,
	image_type: vk.ImageType = .D2,
	levels: u32 = 1,
	layers: u32 = 1,
	faces: u32 = 1,
	is_array: bool = false,
) {
	info := buffer.info
	max_size := info.size
	data := cast([^]u8)info.pMappedData

	assert(info.pMappedData != nil)

	ktx_texture: ^ktx.Texture2
	createInfo := ktx.TextureCreateInfo {
		vkFormat        = format,
		baseWidth       = extent.width,
		baseHeight      = extent.height,
		baseDepth       = extent.depth,
		numDimensions   = u32(image_type) + 1,
		numLevels       = levels,
		numLayers       = layers,
		numFaces        = faces,
		isArray         = is_array,
		generateMipmaps = false,
	}

	ktx.Texture2_Create(&createInfo, .TEXTURE_CREATE_ALLOC_STORAGE, &ktx_texture)

	offset: u32
	for level in 0 ..< levels {
		for face in 0 ..< faces {
			w := extent.width >> level
			h := extent.width >> level

			size := w * h * format_size

			assert(u32(offset) + size <= u32(max_size))

			res := ktx.Texture_SetImageFromMemory(ktx_texture, level, 0, face, data[offset:], uint(size))
			assert(res == .SUCCESS)

			offset += size
		}
	}

	res := ktx.Texture_WriteToNamedFile(ktx_texture, filename)
	assert(res == .SUCCESS)

	ktx.Texture_Destroy(ktx_texture)
}
