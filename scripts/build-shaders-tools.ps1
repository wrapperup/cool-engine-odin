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

exit $LastExitCode
