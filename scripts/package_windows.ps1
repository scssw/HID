New-Item -ItemType Directory -Force -Name "dist\tmp"
New-Item -ItemType Directory -Force -Name "out"

# Copy any setup exe from dist to out
$setupExes = Get-ChildItem -Recurse -File -Path "dist" -Filter "*.exe"
if ($setupExes) {
    Copy-Item $setupExes[0].FullName -Destination "out\Hiddify-Windows-Setup-x64.exe" -Force
    foreach ($exe in $setupExes) {
        Copy-Item $exe.FullName -Destination "out\" -Force
    }
} else {
    Write-Host "Warning: No setup exe found in dist, copying runner Release Hiddify.exe as fallback"
    if (Test-Path "build\windows\x64\runner\Release\Hiddify.exe") {
        Copy-Item "build\windows\x64\runner\Release\Hiddify.exe" -Destination "out\Hiddify-Windows-Setup-x64.exe" -Force
    }
}

Get-ChildItem -Recurse -File -Path "dist" -Filter "*windows.msix" | Copy-Item -Destination "out\Hiddify-Windows-Setup-x64.msix" -ErrorAction SilentlyContinue

# windows portable
xcopy "build\windows\x64\runner\Release" "dist\tmp\hiddify-next" /E/H/C/I/Y
xcopy ".github\help\mac-windows\*.url" "dist\tmp\hiddify-next" /E/H/C/I/Y
Compress-Archive -Force -Path "dist\tmp\hiddify-next" -DestinationPath "out\Hiddify-Windows-Portable-x64.zip" -ErrorAction SilentlyContinue

Remove-Item -Path "$HOME\.pub-cache\git\cache\flutter_circle_flags*" -Force -Recurse -ErrorAction SilentlyContinue

Write-Host "Windows packaging completed. Contents of out:"
Get-ChildItem -Path "out"