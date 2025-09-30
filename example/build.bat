@echo off

slangc ^
    triangle.slang ^
    -profile sm_6_0 ^
    -target spirv ^
    -capability spirv_1_6 ^
    -emit-spirv-directly ^
    -fvk-use-entrypoint-name ^
    -o triangle.spv

odin build . -debug -collection:deps=../deps
