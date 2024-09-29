package gfx

import "base:runtime"
import "core:fmt"
import "core:mem"
import vma "deps:odin-vma"
import vk "vendor:vulkan"

// The deletion queue is implemented a bit differently to the one found
// in vkguide. Since Odin doesn't have convenient lambdas, and since Vulkan
// handles are (usually) all 64-bit pointers/handles, we can generalize an API
// that has similar ergonomics.
//
// The API usage is simpler: Just pass the handle instead of
// a lambda/procedure. If you allocated with VMA, you can also
// pass in the allocation.
//
// The deletion queue is now basically a (crappy) state machine.

DeletionQueue :: struct {
	resource_del_queue: [dynamic]ResourceHandle,
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

vk_destroy_resource :: proc(engine: ^Renderer, resource: ResourceHandle) {
	when false {
		fmt.println("DEBUG: Destroy", resource.ty, "@", resource.caller_location, "-", resource.debug_info)
	}

	if resource_requires_allocation(resource.ty) {
		assert(resource.allocation != nil)
	}

	switch resource.ty {
	case .VmaBuffer:
		vma.DestroyBuffer(engine.allocator, transmute(vk.Buffer)resource.handle, resource.allocation)
	case .VmaImage:
		vma.DestroyImage(engine.allocator, transmute(vk.Image)resource.handle, resource.allocation)
	case .CommandPool:
		vk.DestroyCommandPool(engine.device, transmute(vk.CommandPool)resource.handle, nil)
	case .DescriptorPool:
		vk.DestroyDescriptorPool(engine.device, transmute(vk.DescriptorPool)resource.handle, nil)
	case .DescriptorSetLayout:
		vk.DestroyDescriptorSetLayout(engine.device, transmute(vk.DescriptorSetLayout)resource.handle, nil)
	case .Fence:
		vk.DestroyFence(engine.device, transmute(vk.Fence)resource.handle, nil)
	case .ImageView:
		vk.DestroyImageView(engine.device, transmute(vk.ImageView)resource.handle, nil)
	case .Pipeline:
		vk.DestroyPipeline(engine.device, transmute(vk.Pipeline)resource.handle, nil)
	case .PipelineLayout:
		vk.DestroyPipelineLayout(engine.device, transmute(vk.PipelineLayout)resource.handle, nil)
	case .Sampler:
		vk.DestroySampler(engine.device, transmute(vk.Sampler)resource.handle, nil)
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

push_deletion_queue :: proc(
	queue: ^DeletionQueue,
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

	append(&queue.resource_del_queue, resource_handle)
}

flush_deletion_queue :: proc(engine: ^Renderer, queue: ^DeletionQueue) {
	#reverse for &resource in queue.resource_del_queue {
		vk_destroy_resource(engine, resource)
	}

	clear(&queue.resource_del_queue)
}

delete_deletion_queue :: proc(queue: DeletionQueue) {
	delete(queue.resource_del_queue)
}
