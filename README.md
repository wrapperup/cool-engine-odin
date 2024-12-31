# cool engine
![image](https://github.com/user-attachments/assets/0e3af819-ab20-4298-9110-d058bb5e4003)

Toy engine + Vulkan renderer I built for fun to learn Odin language (and some graphics techniques).

### Features
- Sparse entity system (ECS-like)
- First person player controller based on Unreal character movement
- Skeletal meshes and animation
- Bindless System (see `shaders/text.slang` for a simple example!)
- - Bindless versions of `Texture`, `SamplerState` and `SamplerComparisonState` as handles, while keeping the usage the same.
- - Buffers use BDA
- glTF loading of meshes and skeletal meshes
- Physics (with Physx 5.1)

### Renderer Features
- PBR + IBL + HDR based on [Filament](https://google.github.io/filament/Filament.md.html)
- Point lights
- Tonemapping (tony-mc-mapface)
- Very Crude Text Rendering
- CSM
- Compute skinning
- Tools for baking IBL (irradiance SH and specular cubemaps)

### Screenshots

## Dependencies

 All the dependencies for this project are included as git submodules.
 
 - [odin-imgui](https://gitlab.com/L-4/odin-imgui)
 - [odin-libktx](https://github.com/DanielGavin/odin-libktx)
 - [odin-mikktspace](https://github.com/wrapperup/odin-mikktspace)
 - [odin-slang](https://github.com/DragosPopse/odin-slang)
 - [odin-vma](https://github.com/DanielGavin/odin-vma)
 - [physx-odin](https://github.com/tgolsson/physx-odin)
