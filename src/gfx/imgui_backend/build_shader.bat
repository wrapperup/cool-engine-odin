@echo off
setlocal

slangc imgui.slang ^
    -profile sm_6_0 ^
    -target spirv ^
    -capability spirv_1_6 ^
    -emit-spirv-directly ^
    -fvk-use-entrypoint-name ^
    -o imgui.spv

exit /b 0
