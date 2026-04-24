# 安装网关插件对应的 Python 依赖（单渠道或全部）
# 用法:
#   .\install_deps.ps1
#   .\install_deps.ps1 dingtalk
#   .\install_deps.ps1 all

param(
    [Parameter(Position = 0)]
    [string]$Channel = "all"
)

$Root = $PSScriptRoot
$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) {
    Write-Error "python not found in PATH"
    exit 1
}

& python "$Root\install.py" deps $Channel
exit $LASTEXITCODE
