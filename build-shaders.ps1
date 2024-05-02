slangc shaders/shaders.slang `
    -profile sm_6_0 `
    -target spirv `
    -capability spirv_1_6 `
    -emit-spirv-directly `
    -fvk-use-entrypoint-name `
    -o shaders/out/shaders.spv

slangc shaders/compute.slang `
    -profile sm_6_0 `
    -target spirv `
    -capability spirv_1_6 `
    -emit-spirv-directly `
    -fvk-use-entrypoint-name `
    -o shaders/out/compute.spv

exit $LastExitCode
