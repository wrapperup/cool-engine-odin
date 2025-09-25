@echo off
setlocal

git submodule update --init

set "URL=https://github.com/wrapperup/physx-odin/releases/download/0.1.0/windows-x86_64.tar"
set "OUTDIR=deps\physx-odin"
set "TMPFILE=physx.tar"

echo Downloading %URL% ...
curl -L "%URL%" -o "%TMPFILE%"
if errorlevel 1 (
    echo Download failed!
    exit /b 1
)

echo Extracting files...
tar -xf "%TMPFILE%" -C "%OUTDIR%" physx.lib physx_api.lib physx_api_release.lib physx_release.lib
if errorlevel 1 (
    echo Extraction failed!
    exit /b 1
)

del "%TMPFILE%"

echo Done. Files are in %OUTDIR%.

endlocal
pause
