package main

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
	ty:         ResourceType,
	handle:     u64,
	allocation: vma.Allocation,
}

ResourceType :: enum {
	VmaAllocator,
	VmaBuffer,
	VmaImage,
	CommandPool,
	DescriptorPool,
	Fence,
	ImageView,
	Pipeline,
	PipelineLayout,
}

vk_destroy_resource :: proc(engine: ^VulkanEngine, resource: ResourceHandle) {
	switch resource.ty {
	case .VmaAllocator:
		vma.DestroyAllocator(transmute(vma.Allocator)resource.handle)
	case .VmaBuffer:
		vma.DestroyBuffer(engine.allocator, transmute(vk.Buffer)resource.handle, resource.allocation)
	case .VmaImage:
		vma.DestroyImage(engine.allocator, transmute(vk.Image)resource.handle, resource.allocation)
	case .CommandPool:
		vk.DestroyCommandPool(engine.device, transmute(vk.CommandPool)resource.handle, nil)
	case .DescriptorPool:
		vk.DestroyDescriptorPool(engine.device, transmute(vk.DescriptorPool)resource.handle, nil)
	case .Fence:
		vk.DestroyFence(engine.device, transmute(vk.Fence)resource.handle, nil)
	case .ImageView:
		vk.DestroyImageView(engine.device, transmute(vk.ImageView)resource.handle, nil)
	case .Pipeline:
		vk.DestroyPipeline(engine.device, transmute(vk.Pipeline)resource.handle, nil)
	case .PipelineLayout:
		vk.DestroyPipelineLayout(engine.device, transmute(vk.PipelineLayout)resource.handle, nil)
	}
}

resource_type_of_handle :: proc($T: typeid) -> ResourceType {
	//odinfmt: disable
	return \
		.VmaAllocator when T == vma.Allocator else
		.VmaBuffer when T == vk.Buffer else
		.VmaImage when T == vk.Image else
		.ImageView when T == vk.ImageView else
		.CommandPool when T == vk.CommandPool else
		.DescriptorPool when T == vk.DescriptorPool else
		.Fence when T == vk.Fence else
		.Pipeline when T == vk.Pipeline else
		.PipelineLayout when T == vk.PipelineLayout else
		#panic("Handle type is not a valid resource")
	//odinfmt: enable
}

push_deletion_queue :: proc(queue: ^DeletionQueue, handle: $T, allocation: vma.Allocation = nil) {
	resource_type := resource_type_of_handle(T)

	resource_handle := ResourceHandle {
		handle     = transmute(u64)handle,
		ty         = resource_type,
		allocation = allocation,
	}

	append(&queue.resource_del_queue, resource_handle)
}

flush_deletion_queue :: proc(engine: ^VulkanEngine, queue: ^DeletionQueue) {
	for resource in queue.resource_del_queue {
		vk_destroy_resource(engine, resource)
	}

	clear(&queue.resource_del_queue)
}

delete_deletion_queue :: proc(queue: DeletionQueue) {
	delete(queue.resource_del_queue)
}
