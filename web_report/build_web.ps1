# 包裹管家报表：构建 Windows 一键启动包
# 产物目录：web_report\dist（包含 exe 与 web 前端目录，复制整个 dist 即可分发）

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path $root 'dist'
$exe = Join-Path $dist '包裹管家报表.exe'
$webSource = Join-Path $root 'web'
$webTarget = Join-Path $dist 'web'

Write-Host '1/3 清理旧产物...' -ForegroundColor Cyan
if (Test-Path $dist) {
    Remove-Item $dist -Recurse -Force
}
New-Item -ItemType Directory -Path $dist | Out-Null

Write-Host '2/3 编译可执行文件...' -ForegroundColor Cyan
dart compile exe (Join-Path $root 'server.dart') -o $exe
if ($LASTEXITCODE -ne 0) {
    throw "dart compile exe 失败，退出码 $LASTEXITCODE"
}

Write-Host '3/3 复制前端资源...' -ForegroundColor Cyan
Copy-Item $webSource $webTarget -Recurse -Force

Write-Host ''
Write-Host '构建完成！' -ForegroundColor Green
Write-Host "双击运行：$exe"
Write-Host '运行后会自动打开浏览器，数据保存在浏览器本地，关闭窗口后再次打开仍可查看。'
