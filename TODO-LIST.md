# Things to do

## Usability
- [x] Window resizing / minimizing
- [x] Full screen toggle

## Cleanup
- [ ] Cleanup renderer
- - [x] Window should just be handled by the renderer? messy...
- - [ ] Combine init functions (it's fragmented to like 100 functions bruh)
- - [ ] Bindless system should be part of core GFX
- - [ ] Combine GFX with main program?

## General
- [ ] Asset system (UUID based)
- - [ ] Sounds
- - [ ] GLTF Meshes
- - [ ] GLTF SkelMeshes
- - [ ] Hard-coded Assets (for testing)
- - [ ] File-based Assets (metadata? full binary?)
- - [ ] Switch all hard-coded paths to use asset system

## Scene management
- [ ] Switch to Odin-native gltf2 library? (to make custom ext's cleaner)
- [ ] Load entire scene from gltf
- - [ ] Static Meshes
- - [ ] Punctual lights
- - [ ] Irradiance Volumes
- - [ ] Loading Assets (map to UUID? Needs asset system)

## Graphics
- [ ] Make shadow map follow camera
- [ ] Shadow Cascades
- [ ] Irradiance Volumes
- - [x] Bake from Blender
- - [ ] Implement with IBL/Mesh shading
- - [ ] Trilinear Interpolation
- [ ] Render Pass Abstraction
- [ ] Render Graph
