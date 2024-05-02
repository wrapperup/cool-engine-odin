# VkGuide in Odin

Follows [vkguide](https://vkguide.dev/) implementations with a few differences:

1. No vkbootstrap. Initialization is part of this project's code. features,
extensions, and validation layers are defined in `config.odin`, and are used to pick the best device.
2. Shaders are written in [slang](https://github.com/shader-slang/slang). `slangc` is expected to be in PATH.
   - Using slang-specific features (mostly pointers for BDA)

## Dependencies

 All the dependencies for this project are included as git submodules.
 
 - [odin-vma](https://github.com/DanielGavin/odin-vma)
 - [odin-imgui](https://gitlab.com/L-4/odin-imgui)
