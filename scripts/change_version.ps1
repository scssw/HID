[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "                Hiddify 一键修改版本号工具                    " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$baseDir = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($baseDir) -or -not (Test-Path (Join-Path $baseDir "pubspec.yaml"))) {
    $baseDir = Get-Location
}

# 1. 尝试读取当前版本号
$pubspecPath = Join-Path $baseDir "pubspec.yaml"
$currentVer = "未知"
if (Test-Path $pubspecPath) {
    $pubContent = [System.IO.File]::ReadAllText($pubspecPath, [System.Text.Encoding]::UTF8)
    if ($pubContent -match '(?m)^version:\s*([^\r\n]+)$') {
        $currentVer = $matches[1]
    }
}

Write-Host "当前版本号: " -NoNewline -ForegroundColor Yellow
Write-Host "$currentVer" -ForegroundColor White
Write-Host ""

# 2. 获取用户输入
$newVersionInput = ""
if ($args.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($args[0])) {
    $newVersionInput = $args[0].Trim()
}

while ([string]::IsNullOrWhiteSpace($newVersionInput)) {
    Write-Host "请输入新版本号 (例如 3.0.1 或 3.0.2+30002): " -NoNewline -ForegroundColor Green
    $inputVal = Read-Host
    if (-not [string]::IsNullOrWhiteSpace($inputVal)) {
        $newVersionInput = $inputVal.Trim()
    }
}

# 3. 解析版本号和构建号
# 匹配类似 3.0.1 或 3.0.1+30001
$verPattern = '^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$'
if ($newVersionInput -notmatch $verPattern) {
    Write-Host ""
    Write-Host "错误: 版本号格式不正确！必须是类似 '3.0.1' 或 '3.0.1+30001' 的格式。" -ForegroundColor Red
    exit 1
}

$major = [int]$matches[1]
$minor = [int]$matches[2]
$patch = [int]$matches[3]
$verStr = "$($major).$($minor).$($patch)"

if ($matches[4]) {
    $buildStr = $matches[4]
} else {
    $calcBuild = $major * 10000 + $minor * 100 + $patch
    $buildStr = $calcBuild.ToString()
}

$fullVersion = "$($verStr)+$($buildStr)"
$msixVersion = "$($verStr).0"

Write-Host ""
Write-Host "即将应用的新版本信息:" -ForegroundColor Cyan
Write-Host "  版本号 (Version)      : $verStr" -ForegroundColor White
Write-Host "  构建号 (BuildNumber)  : $buildStr" -ForegroundColor White
Write-Host "  完整版本 (FullVersion): $fullVersion" -ForegroundColor White
Write-Host "  MSIX版本 (MsixVersion): $msixVersion" -ForegroundColor White
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

$filesUpdated = 0

# 1. 更新 lib\core\app_info\app_info_provider.dart
$appInfoPath = Join-Path $baseDir "lib\core\app_info\app_info_provider.dart"
if (Test-Path $appInfoPath) {
    $content = [System.IO.File]::ReadAllText($appInfoPath, [System.Text.Encoding]::UTF8)
    $content = $content -replace 'version:\s*"[^"]*"', "version: `"$verStr`""
    $content = $content -replace 'buildNumber:\s*"[^"]*"', "buildNumber: `"$buildStr`""
    [System.IO.File]::WriteAllText($appInfoPath, $content, $utf8NoBom)
    Write-Host "[✓] 已更新: lib\core\app_info\app_info_provider.dart" -ForegroundColor Green
    $filesUpdated++
} else {
    Write-Host "[!] 未找到: $appInfoPath" -ForegroundColor Yellow
}

# 2. 更新 pubspec.yaml
if (Test-Path $pubspecPath) {
    $content = [System.IO.File]::ReadAllText($pubspecPath, [System.Text.Encoding]::UTF8)
    $content = $content -replace '(?m)^version:\s*[^\r\n]+$', "version: $fullVersion"
    [System.IO.File]::WriteAllText($pubspecPath, $content, $utf8NoBom)
    Write-Host "[✓] 已更新: pubspec.yaml" -ForegroundColor Green
    $filesUpdated++
} else {
    Write-Host "[!] 未找到: $pubspecPath" -ForegroundColor Yellow
}

# 3. 更新 windows\packaging\msix\make_config.yaml
$msixPath = Join-Path $baseDir "windows\packaging\msix\make_config.yaml"
if (Test-Path $msixPath) {
    $content = [System.IO.File]::ReadAllText($msixPath, [System.Text.Encoding]::UTF8)
    $content = $content -replace '(?m)^msix_version:\s*[^\r\n]+$', "msix_version: $msixVersion"
    [System.IO.File]::WriteAllText($msixPath, $content, $utf8NoBom)
    Write-Host "[✓] 已更新: windows\packaging\msix\make_config.yaml" -ForegroundColor Green
    $filesUpdated++
} else {
    Write-Host "[!] 未找到: $msixPath" -ForegroundColor Yellow
}

# 4. 更新 windows\runner\CMakeLists.txt
$cmakePath = Join-Path $baseDir "windows\runner\CMakeLists.txt"
if (Test-Path $cmakePath) {
    $content = [System.IO.File]::ReadAllText($cmakePath, [System.Text.Encoding]::UTF8)
    $content = $content -replace 'set\(FLUTTER_VERSION\s+"[^"]*"\)', "set(FLUTTER_VERSION `"$fullVersion`")"
    $content = $content -replace 'set\(FLUTTER_VERSION_MAJOR\s+\d+\)', "set(FLUTTER_VERSION_MAJOR $major)"
    $content = $content -replace 'set\(FLUTTER_VERSION_MINOR\s+\d+\)', "set(FLUTTER_VERSION_MINOR $minor)"
    $content = $content -replace 'set\(FLUTTER_VERSION_PATCH\s+\d+\)', "set(FLUTTER_VERSION_PATCH $patch)"
    $content = $content -replace 'set\(FLUTTER_VERSION_BUILD\s+\d+\)', "set(FLUTTER_VERSION_BUILD $buildStr)"
    [System.IO.File]::WriteAllText($cmakePath, $content, $utf8NoBom)
    Write-Host "[✓] 已更新: windows\runner\CMakeLists.txt" -ForegroundColor Green
    $filesUpdated++
} else {
    Write-Host "[!] 未找到: $cmakePath" -ForegroundColor Yellow
}

# 5. 更新 构建.txt (如果存在)
$buildTxtPath = Join-Path $baseDir "构建.txt"
if (Test-Path $buildTxtPath) {
    $content = [System.IO.File]::ReadAllText($buildTxtPath, [System.Text.Encoding]::UTF8)
    $content = $content -replace 'pubspec\.yaml:\d+\s*→\s*version:\s*[^\r\n]+', "pubspec.yaml:4 → version: $fullVersion"
    $content = $content -replace 'make_config\.yaml:\d+\s*→\s*msix_version:\s*[^\r\n]+', "make_config.yaml:4 → msix_version: $msixVersion"
    [System.IO.File]::WriteAllText($buildTxtPath, $content, $utf8NoBom)
    Write-Host "[✓] 已更新: 构建.txt" -ForegroundColor Green
    $filesUpdated++
}

Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "全部完成！共更新 $filesUpdated 个文件中的版本配置。" -ForegroundColor Green
Write-Host "新版本已生效: $fullVersion" -ForegroundColor Green
Write-Host ""
