@echo off
setlocal

set META_EXE=build\meta.exe
set META_BUILD_SCRIPT=build-meta.bat

if not exist "build" (
    mkdir "build"
)

if not exist "build/debug" (
    mkdir "build/debug"
)

if not exist "%META_EXE%" (
    echo Metaprogram missing, building...
    call %META_BUILD_SCRIPT%
)

:: Run metaprogram
%META_EXE%

set BASE_FLAGS=src ^
    -collection:deps=deps ^
    -custom-attribute:shader_shared ^
    -show-timings ^
    -extra-linker-flags:/NODEFAULTLIB:libcmt ^
    -linker:radlink

:: If first arg is "1", do release; otherwise debug
if "%~1"=="1" (
    set FLAGS=%BASE_FLAGS% ^
        -o:speed ^
        -out:build/release/main.exe
) else (
    set FLAGS=%BASE_FLAGS% ^
        -debug ^
        -o:none ^
        -out:build/debug/main.exe
)

odin build %FLAGS% || exit /b %ERRORLEVEL%

exit /b 0
