@echo off
setlocal

set FLAGS=^
    -collection:deps=deps ^
    -custom-attribute:shader_shared ^
    -debug ^
    -o:none ^
    -show-timings ^
    -define:GENERATING_META=true

odin build src -out:build/meta.exe %FLAGS% || exit /b %ERRORLEVEL%
