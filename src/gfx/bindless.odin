package gfx

import "core:fmt"
import vk "vendor:vulkan"

MAX_BINDLESS_IMAGES :: 100
MAX_BINDLESS_SAMPLERS :: 32

BINDLESS_SAMPLED_IMAGES: u32 : 0
BINDLESS_SAMPLERS: u32 : 1
BINDLESS_STORAGE_IMAGES: u32 : 2

ImageId :: distinct u32
SamplerId :: distinct u32

CombinedImageId :: bit_field u64 {
	rw_image:   bool      | 1,
	sampler_id: SamplerId | 31,
	image_id:   ImageId   | 32,
}

BindlessSystem :: struct {
	descriptor_layout:  vk.DescriptorSetLayout,
	descriptor_set:     vk.DescriptorSet,

	// Storage
	images:             [dynamic]GPUImage,
	free_image_slots:   [dynamic]int,
	samplers:           [dynamic]vk.Sampler,
	free_sampler_slots: [dynamic]int,
}

init_bindless_descriptors :: proc() {
	bindless_system := &r_ctx.bindless_system

	bindless_system.descriptor_layout = create_descriptor_set_layout(
		{
			{binding = BINDLESS_SAMPLED_IMAGES, type = .SAMPLED_IMAGE, count = MAX_BINDLESS_IMAGES},
			{binding = BINDLESS_SAMPLERS, type = .SAMPLER, count = MAX_BINDLESS_SAMPLERS},
			{binding = BINDLESS_STORAGE_IMAGES, type = .STORAGE_IMAGE, count = MAX_BINDLESS_IMAGES},
		},
		{.UPDATE_AFTER_BIND_POOL},
		{.VERTEX, .FRAGMENT, .COMPUTE},
	)
	defer_destroy(&r_ctx.global_arena, bindless_system.descriptor_layout)

	bindless_system.descriptor_set = allocate_descriptor_set(
		&r_ctx.global_descriptor_allocator,
		r_ctx.device,
		bindless_system.descriptor_layout,
	)
}

add_gpu_image :: proc(image: GPUImage) -> ImageId {
	bindless_system := &r_ctx.bindless_system

	assert(.STORAGE in image.usage || .SAMPLED in image.usage)

	image_id := ImageId(0)

	if len(bindless_system.free_image_slots) > 0 {
		image_id = ImageId(pop(&bindless_system.free_image_slots))
		bindless_system.images[image_id] = image
	} else {
		image_id = ImageId(u32(len(bindless_system.images)))
		append(&bindless_system.images, image)
	}

	if .STORAGE in image.usage {
		write_descriptor_set(
			bindless_system.descriptor_set,
			{
				{
					binding = BINDLESS_STORAGE_IMAGES,
					type = .STORAGE_IMAGE,
					image_view = image.image_view,
					image_layout = .GENERAL,
					array_index = u32(image_id),
				},
			},
		)
	}

	if .SAMPLED in image.usage {
		write_descriptor_set(
			bindless_system.descriptor_set,
			{
				{
					binding = BINDLESS_SAMPLED_IMAGES,
					type = .SAMPLED_IMAGE,
					image_view = image.image_view,
					image_layout = .GENERAL,
					array_index = u32(image_id),
				},
			},
		)
	}

	return image_id
}

add_gpu_image_with_view :: proc(image: GPUImage, view: vk.ImageView) -> ImageId {
	image := image
	image.image_view = view
	return add_gpu_image(image)
}

add_image :: proc {
	add_gpu_image,
	add_gpu_image_with_view,
}

remove_image :: proc(image_id: ImageId) -> bool {
	image_id := int(image_id)

	bindless_system := &r_ctx.bindless_system
	assert(image_id >= len(bindless_system.images))

	for i in bindless_system.free_image_slots {
		if i == image_id {
			return false // Tried double freeing
		}
	}

	append(&bindless_system.free_image_slots, image_id)

	return true
}

add_sampler :: proc(sampler: vk.Sampler) -> SamplerId {
	bindless_system := &r_ctx.bindless_system

	sampler_id := SamplerId(u32(len(bindless_system.samplers)))
	append(&bindless_system.samplers, sampler)

	write_descriptor_set(
		bindless_system.descriptor_set,
		{{binding = BINDLESS_SAMPLERS, type = .SAMPLER, sampler = sampler, array_index = u32(sampler_id)}},
	)

	return sampler_id
}

remove_sampler :: proc(sampler_id: SamplerId) -> bool {
	sampler_id := int(sampler_id)

	bindless_system := &r_ctx.bindless_system
	assert(sampler_id >= len(bindless_system.samplers))

	for i in bindless_system.free_sampler_slots {
		if i == sampler_id {
			return false // Tried double freeing
		}
	}

	append(&bindless_system.free_sampler_slots, sampler_id)

	return true
}

// // Writes a image to the bindless ID and updates the descriptor.
// set_image :: proc(image: GPUImage, image_id: ImageId) -> (resized: bool) {
// 	bindless_system := &r_ctx.bindless_system
//
// 	// Ensure our image id can fit
// 	if ImageId(len(bindless_system.bindless_images)) <= image_id {
// 		resize(&bindless_system.bindless_images, image_id + 1)
// 		resized = true
// 	}
//
// 	bindless_system.bindless_images[image_id] = image
//
// 	write_descriptor_set(
// 		bindless_system.descriptor_set,
// 		{
// 			{
// 				binding = 0,
// 				type = .SAMPLED_IMAGE,
// 				image_view = image.image_view,
// 				image_layout = .READ_ONLY_OPTIMAL,
// 				array_index = u32(image_id),
// 			},
// 		},
// 	)
//
// 	return
// }
