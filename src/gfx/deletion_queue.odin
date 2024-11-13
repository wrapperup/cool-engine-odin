package gfx

import "base:runtime"
import "core:fmt"
import "core:mem"
import vma "deps:odin-vma"
import vk "vendor:vulkan"

// The deletion arena is implemented a bit differently to the one found
// in vkguide. Since Odin doesn't have convenient lambdas, and since Vulkan
// handles are (usually) all 64-bit pointers/handles, we can generalize an API
// that has similar ergonomics.
//
// The API usage is simpler: Just pass the handle instead of
// a lambda/procedure. If you allocated with VMA, you can also
// pass in the allocation.
//
// The deletion arena is now basically a (crappy) state machine.

VulkanArena :: struct {
	resource_arena: [dynamic]ResourceHandle,
}

ResourceHandle :: struct {
	ty:              ResourceType,
	handle:          u64,
	allocation:      vma.Allocation,
	debug_info:      string,
	caller_location: runtime.Source_Code_Location,
}

ResourceType :: enum {
	VmaBuffer,
	VmaImage,
	CommandPool,
	DescriptorPool,
	DescriptorSetLayout,
	Fence,
	ImageView,
	Pipeline,
	PipelineLayout,
	Sampler,
}

destroy_resource :: proc(
	handle: $T,
	allocation: vma.Allocation = nil,
) {
	when T == vk.Buffer || T == vk.Image {
		when allocation == nil {
			#assert(false)
		}
	}

	ty := resource_type_of_handle(T)

	switch ty {
	case .VmaBuffer:
		vma.DestroyBuffer(r_ctx.allocator, transmute(vk.Buffer)resource.handle, resource.allocation)
	case .VmaImage:
		vma.DestroyImage(r_ctx.allocator, transmute(vk.Image)resource.handle, resource.allocation)
	case .CommandPool:
		vk.DestroyCommandPool(r_ctx.device, transmute(vk.CommandPool)resource.handle, nil)
	case .DescriptorPool:
		vk.DestroyDescriptorPool(r_ctx.device, transmute(vk.DescriptorPool)resource.handle, nil)
	case .DescriptorSetLayout:
		vk.DestroyDescriptorSetLayout(r_ctx.device, transmute(vk.DescriptorSetLayout)resource.handle, nil)
	case .Fence:
		vk.DestroyFence(r_ctx.device, transmute(vk.Fence)resource.handle, nil)
	case .ImageView:
		vk.DestroyImageView(r_ctx.device, transmute(vk.ImageView)resource.handle, nil)
	case .Pipeline:
		vk.DestroyPipeline(r_ctx.device, transmute(vk.Pipeline)resource.handle, nil)
	case .PipelineLayout:
		vk.DestroyPipelineLayout(r_ctx.device, transmute(vk.PipelineLayout)resource.handle, nil)
	case .Sampler:
		vk.DestroySampler(r_ctx.device, transmute(vk.Sampler)resource.handle, nil)
	}
}

vk_destroy_resource_by_handle :: proc(resource: ResourceHandle) {
	when false {
		log_normal("DEBUG: Destroy", resource.ty, "@", resource.caller_location, "-", resource.debug_info)
	}

	if resource_requires_allocation(resource.ty) {
		assert(resource.allocation != nil)
	}

	switch resource.ty {
	case .VmaBuffer:
		vma.DestroyBuffer(r_ctx.allocator, transmute(vk.Buffer)resource.handle, resource.allocation)
	case .VmaImage:
		vma.DestroyImage(r_ctx.allocator, transmute(vk.Image)resource.handle, resource.allocation)
	case .CommandPool:
		vk.DestroyCommandPool(r_ctx.device, transmute(vk.CommandPool)resource.handle, nil)
	case .DescriptorPool:
		vk.DestroyDescriptorPool(r_ctx.device, transmute(vk.DescriptorPool)resource.handle, nil)
	case .DescriptorSetLayout:
		vk.DestroyDescriptorSetLayout(r_ctx.device, transmute(vk.DescriptorSetLayout)resource.handle, nil)
	case .Fence:
		vk.DestroyFence(r_ctx.device, transmute(vk.Fence)resource.handle, nil)
	case .ImageView:
		vk.DestroyImageView(r_ctx.device, transmute(vk.ImageView)resource.handle, nil)
	case .Pipeline:
		vk.DestroyPipeline(r_ctx.device, transmute(vk.Pipeline)resource.handle, nil)
	case .PipelineLayout:
		vk.DestroyPipelineLayout(r_ctx.device, transmute(vk.PipelineLayout)resource.handle, nil)
	case .Sampler:
		vk.DestroySampler(r_ctx.device, transmute(vk.Sampler)resource.handle, nil)
	}
}

resource_type_of_handle :: proc($T: typeid) -> ResourceType {
	//odinfmt: disable
	return \
		.VmaBuffer when T == vk.Buffer else
		.VmaImage when T == vk.Image else
		.ImageView when T == vk.ImageView else
		.CommandPool when T == vk.CommandPool else
		.DescriptorPool when T == vk.DescriptorPool else
		.DescriptorSetLayout when T == vk.DescriptorSetLayout else
		.Fence when T == vk.Fence else
		.Pipeline when T == vk.Pipeline else
		.PipelineLayout when T == vk.PipelineLayout else
		.Sampler when T == vk.Sampler else
		#panic("Handle type is not a valid resource")
	//odinfmt: enable
}

type_requires_allocation :: proc($T: typeid) -> bool {
	return \
		true when T == vk.Buffer else
		true when T == vk.Image else
		false
	//odinfmt: enable
}

resource_requires_allocation :: proc(type: ResourceType) -> bool {
	#partial switch type {
	case .VmaBuffer:
		return true
	case .VmaImage:
		return true
	case:
		return false
	}
}

defer_destroy :: proc(
	arena: ^VulkanArena,
	handle: $T,
	allocation: vma.Allocation = nil,
	debug: string = "UNKNOWN",
	loc: runtime.Source_Code_Location = #caller_location,
) {
	resource_type := resource_type_of_handle(T)

	if resource_requires_allocation(resource_type) {
		assert(allocation != nil, "Resource of this type requires an allocation to be passed in.", loc)
	}

	resource_handle := ResourceHandle {
		handle          = transmute(u64)handle,
		ty              = resource_type,
		allocation      = allocation,
		debug_info      = debug,
		caller_location = loc,
	}

	append(&arena.resource_arena, resource_handle)
}

defer_destroy_buffer :: proc(
	arena: ^VulkanArena,
	buffer: GPUBuffer,
	debug: string = "UNKNOWN",
	loc: runtime.Source_Code_Location = #caller_location,
) {
	defer_destroy(arena, buffer.buffer, buffer.allocation);
}

flush_vk_arena :: proc(arena: ^VulkanArena) {
	#reverse for &resource in arena.resource_arena {
		vk_destroy_resource_by_handle(resource)
	}

	clear(&arena.resource_arena)
}

delete_vk_arena :: proc(arena: VulkanArena) {
	delete(arena.resource_arena)
}
