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

BindlessSystem :: struct {
	descriptor_layout: vk.DescriptorSetLayout,
	descriptor_set:    vk.DescriptorSet,

	// Storage
	images:            [dynamic]GPUImage,
	samplers:          [dynamic]vk.Sampler,
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

add_image :: proc(image: GPUImage) -> ImageId {
	bindless_system := &r_ctx.bindless_system

	image_id := ImageId(u32(len(bindless_system.images)))
	append(&bindless_system.images, image)

	assert(.STORAGE in image.usage || .SAMPLED in image.usage)

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
