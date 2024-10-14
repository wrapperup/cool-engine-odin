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
    shaders/prefilter_env.slang `
    -profile sm_6_0 `
    -target spirv `
    -capability spirv_1_6 `
    -emit-spirv-directly `
    -fvk-use-entrypoint-name `
    -Wno-39001 `
    -o shaders/out/prefilter_env.spv

exit $LastExitCode
