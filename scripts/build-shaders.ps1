slangc `
    shaders/mesh.slang `
    -profile sm_6_0 `
    -target spirv `
    -capability spirv_1_6 `
    -emit-spirv-directly `
    -fvk-use-entrypoint-name `
    -Wno-39001 `
    -o shaders/out/shaders.spv

slangc `
    shaders/tonemapping.slang `
    -profile sm_6_0 `
    -target spirv `
    -capability spirv_1_6 `
    -emit-spirv-directly `
    -fvk-use-entrypoint-name `
    -Wno-39001 `
    -o shaders/out/tonemapping.spv

slangc `
    shaders/tools/prefilter_env.slang `
    -profile sm_6_0 `
    -target spirv `
    -capability spirv_1_6 `
    -emit-spirv-directly `
    -fvk-use-entrypoint-name `
    -Wno-39001 `
    -o shaders/out/prefilter_env.spv

slangc `
    shaders/tools/dfg.slang `
    -profile sm_6_0 `
    -target spirv `
    -capability spirv_1_6 `
    -emit-spirv-directly `
    -fvk-use-entrypoint-name `
    -Wno-39001 `
    -o shaders/out/dfg.spv

slangc `
    shaders/tools/spherical_harmonics.slang `
    -profile sm_6_0 `
    -target spirv `
    -capability spirv_1_6 `
    -emit-spirv-directly `
    -fvk-use-entrypoint-name `
    -Wno-39001 `
    -o shaders/out/spherical_harmonics.spv

slangc `
    shaders/skybox.slang `
    -profile sm_6_0 `
    -target spirv `
    -capability spirv_1_6 `
    -emit-spirv-directly `
    -fvk-use-entrypoint-name `
    -Wno-39001 `
    -o shaders/out/skybox.spv

slangc `
    shaders/skinning.slang `
    -profile sm_6_0 `
    -target spirv `
    -capability spirv_1_6 `
    -emit-spirv-directly `
    -fvk-use-entrypoint-name `
    -Wno-39001 `
    -o shaders/out/skinning.spv

exit $LastExitCode
