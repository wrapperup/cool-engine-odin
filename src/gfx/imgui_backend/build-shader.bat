@echo off
setlocal

set SCRIPT_DIR=%~dp0
set SLANGC=%SCRIPT_DIR%..\..\..\deps\odin-slang\slang\bin\slangc.exe
set INCLUDE=%SCRIPT_DIR%..\..\..\shaders

"%SLANGC%" "%SCRIPT_DIR%imgui.slang" ^
    -I "%INCLUDE%" ^
    -target spirv ^
    -emit-spirv-directly ^
    -profile sm_6_0 ^
    -fvk-use-entrypoint-name ^
    -force-glsl-scalar-layout ^
    -matrix-layout-column-major ^
    -o "%SCRIPT_DIR%imgui.spv" || exit /b %ERRORLEVEL%

echo Built imgui.spv
