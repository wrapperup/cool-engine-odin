package gfx

import "core:mem"

import vk "vendor:vulkan"

import ktx "deps:odin-libktx"
import vma "deps:odin-vma"

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
