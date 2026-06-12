# Things to do

## Usability
- [x] Window resizing / minimizing
- [x] Full screen toggle

## Shaders
- [x] Bindless solution
- [x] Generate shared types

## Entity System
- [ ] Use metaprogram?
- [ ] Deleting untyped/raw entity and it's subtype via reflection (for ed/debug)

## General
- [ ] Fixed ticks for everything
- [ ] Asset system
- - [ ] File-based
- - [ ] File-based

## Scene management
- [ ] Switch to Odin-native gltf2 library? (to make custom ext's cleaner)
- [ ] Load entire scene from gltf
- - [ ] Static Meshes
- - [ ] Punctual lights
- - [ ] Irradiance Volumes
- - [ ] Map and load assets

## Graphics
- [x] Make shadow map follow camera
- [x] Shadow Cascades
- [ ] Irradiance Volumes
- - [ ] Bake from Blender
- - [ ] Implement with IBL/Mesh shading
- - [ ] Trilinear Interpolation
- [ ] Render Pass Abstraction
- [ ] Render Graph

## Blender Editor (IPC) Plugin
- [ ] Spawn Entities by type (?)

## Cleanup
- [ ] Destroy old swapchains
- [ ] Cleanup renderer
- - [x] Window should just be handled by the renderer? messy...
- - [ ] Combine init functions (it's fragmented to like 100 functions bruh)
- - [ ] Bindless system should be part of core GFX
- - [ ] Combine GFX with main program?
