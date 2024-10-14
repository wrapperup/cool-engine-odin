package tools

import "core:fmt"
import "core:sys/windows"
import "core:mem"
import "core:time"

import vk "vendor:vulkan"

import "../src/gfx"
import ktx "deps:odin-libktx"
import vma "deps:odin-vma"

main :: proc() {
	when ODIN_OS == .Windows {
		// Use UTF-8 for console output (fixes emojis/unicode/utf-8 shenanigans)
		windows.SetConsoleOutputCP(.UTF8)
	}
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	start_time := time.now()

	calculate_dfg_to_file("testing.ktx")

	fmt.println("Done in", time.since(start_time))
}

calculate_dfg_to_file :: proc(filename: cstring, width: u32 = 256, height: u32 = 256) {
	gfx.init()

	width: u32 = 256
	height: u32 = 256

	extent := vk.Extent3D{256, 256, 1}

	fmt.println("Generating DFG image...")
	dfg := create_dfg_generate_pipeline()
	if cmd, ok := gfx.immediate_submit(); ok {
		gfx.transition_image(cmd, dfg.dfg_image.image, .UNDEFINED, .GENERAL)
		run_dfg_generate_pass(&dfg, cmd)

		region := vk.BufferImageCopy {
			imageOffset = {0, 0, 0},
			imageExtent = {width, height, 1},
			bufferOffset = 0,
			bufferRowLength = width,
			bufferImageHeight = height,
			imageSubresource = {mipLevel = 0, layerCount = 1, aspectMask = {.COLOR}, baseArrayLayer = 0},
		}

		// Copy image to staging buffer
		vk.CmdCopyImageToBuffer(cmd, dfg.dfg_image.image, .GENERAL, dfg.dfg_image_mapped_buffer.buffer, 1, &region)
	}

	fmt.println("Writing DFG image to", filename)

	write_buffer_to_ktx_file(filename, &dfg.dfg_image_mapped_buffer, extent, .R16G16_SFLOAT)

	gfx.shutdown()
}

write_buffer_to_ktx_file :: proc(
	filename: cstring,
	buffer: ^gfx.AllocatedBuffer,
	extent: vk.Extent3D,
	format: vk.Format,
	image_type: vk.ImageType = .D2,
	levels: u32 = 1,
	layers: u32 = 1,
	faces: u32 = 1,
	is_array: bool = false,
) {
	info := buffer.info
	size := info.size
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

	res := ktx.Texture_SetImageFromMemory(ktx_texture, 0, 0, 0, data, uint(size))
	assert(res == .SUCCESS)

	res = ktx.Texture_WriteToNamedFile(ktx_texture, filename)
	assert(res == .SUCCESS)

	ktx.Texture_Destroy(ktx_texture)
}
