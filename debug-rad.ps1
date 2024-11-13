$process = Get-Process raddbg -ErrorAction SilentlyContinue
if ($process -eq $null) {
        Start-Process -FilePath "raddbg.exe" -ArgumentList "--project ./debug.raddbg_project"
} else {
        Start-Process -FilePath "raddbg.exe" -ArgumentList "--ipc run"
}
