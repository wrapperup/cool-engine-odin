$process = Get-Process raddbg -ErrorAction SilentlyContinue
if ($process -eq $null) {
        Start-Process -FilePath "raddbg.exe" -ArgumentList "--auto_run ./build/main.exe"
} else {
        Start-Process -FilePath "raddbg.exe" -ArgumentList "--ipc run"
}
