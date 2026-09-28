New-Item -ItemType Directory -Force -Name "out"

# Locate Inno Setup compiler
$isccPath = "iscc"
if (Test-Path "C:\Program Files (x86)\Inno Setup 6\ISCC.exe") {
    $isccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
} elseif (Test-Path "C:\Program Files\Inno Setup 6\ISCC.exe") {
    $isccPath = "C:\Program Files\Inno Setup 6\ISCC.exe"
}

Write-Host "Compiling Windows installer with $isccPath..."
& $isccPath "windows\runner\hiddify_setup.iss"

if (Test-Path "out\Hiddify-Windows-Setup-x64.exe") {
    $sizeMb = [math]::Round(((Get-Item "out\Hiddify-Windows-Setup-x64.exe").Length / 1MB), 2)
    Write-Host "Installer created successfully: out\Hiddify-Windows-Setup-x64.exe (${sizeMb} MB)"
} else {
    Write-Error "CRITICAL: out\Hiddify-Windows-Setup-x64.exe was not created!"
}

# Windows portable ZIP
New-Item -ItemType Directory -Force -Name "dist\tmp\hiddify-next"
xcopy "build\windows\x64\runner\Release" "dist\tmp\hiddify-next" /E/H/C/I/Y
xcopy ".github\help\mac-windows\*.url" "dist\tmp\hiddify-next" /E/H/C/I/Y
Compress-Archive -Force -Path "dist\tmp\hiddify-next\*" -DestinationPath "out\Hiddify-Windows-Portable-x64.zip"

Write-Host "Windows packaging completed. Contents of out/:"
Get-ChildItem -Path "out"