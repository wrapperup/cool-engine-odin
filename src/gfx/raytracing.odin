package gfx

import vk "vendor:vulkan"

Raytracing_Accel :: struct {
    accel: vk.AccelerationStructureKHR,
    buffer: GPUBuffer(u8),
    address: vk.DeviceAddress,
}
