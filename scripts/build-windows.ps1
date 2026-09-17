<#
.SYNOPSIS
    DeepSeek Harness Desktop Windows Release (x86_64 / x64) 本地一键构建脚本

.DESCRIPTION
    本脚本复刻并增强了 GitHub Actions (.github/workflows/build-windows.yml) 的打包流程：
    1. 检测并准备 Git、Node.js (>=22.19.0) 与 pnpm (11.7.0)；若本地缺失 Node 22，支持自动下载便携版至 .tools/ 目录；
    2. 克隆官方上游仓库 deepseek-ai/deepseek-harness 并检出指定基线提交 c389f96bf3a9b6807cb71ed6bdad5849be0df6d8；
    3. 解压并应用 patches/desktop-customizations.patch.zip 定制补丁；
    4. 安装依赖并编译 Typert Remote 协议与 host 依赖；
    5. 配置免证书打包模式并执行打包生成 Windows x64 安装程序；
    6. 将产物归档至 release/ 目录并生成 SHA-256 校验和。

.PARAMETER SourceDir
    上游源码存放路径，默认为 <项目根目录>/source

.PARAMETER OutputDir
    安装包发布目录，默认为 <项目根目录>/release

.PARAMETER SkipClone
    若上游源码已存在，跳过克隆与检出步骤

.PARAMETER SkipInstall
    跳过 pnpm install 依赖安装步骤

.PARAMETER Registry
    指定 npm/pnpm 镜像源（如 https://registry.npmmirror.com）
#>

[CmdletBinding()]
param (
    [string]$SourceDir = "",
    [string]$OutputDir = "",
    [switch]$SkipClone,
    [switch]$SkipInstall,
    [string]$Registry = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    $SourceDir = Join-Path $RepoRoot "source"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RepoRoot "release"
}

$ToolsDir = Join-Path $RepoRoot ".tools"
$NodeVersion = "22.23.2"
$PnpmVersion = "11.7.0"
$BaselineCommit = "c389f96bf3a9b6807cb71ed6bdad5849be0df6d8"
$UpstreamRepo = "https://github.com/deepseek-ai/deepseek-harness.git"

function Write-Step {
    param ([string]$Message)
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "[STEP] $Message" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Cyan
}

function Write-Warn {
    param ([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Success {
    param ([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

# -------------------------------------------------------------
# 步骤 1: 检查基础环境 (Git, Node.js, pnpm)
# -------------------------------------------------------------
Write-Step "1/6 检查构建环境..."

# 检查 Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "未找到 Git 命令，请先安装 Git 并添加到系统 PATH。"
}
$gitVersion = (git --version)
Write-Host "Git: $gitVersion" -ForegroundColor Gray

# 检查 Node.js
$targetNode = $null
$systemNode = Get-Command node -ErrorAction SilentlyContinue
if ($systemNode) {
    try {
        $vStr = (& node -v).TrimStart('v')
        $vParts = $vStr.Split('.')
        $major = [int]$vParts[0]
        $minor = [int]$vParts[1]
        if ($major -gt 22 -or ($major -eq 22 -and $minor -ge 19)) {
            $targetNode = $systemNode.Source
            Write-Host "系统 Node.js 满足版本要求: v$vStr ($targetNode)" -ForegroundColor Gray
        } else {
            Write-Warn "系统 Node.js 版本 (v$vStr) 低于项目要求的 v22.19.0。"
        }
    } catch {
        Write-Warn "检测系统 Node.js 版本失败。"
    }
}

# 如果没有满足条件的 Node.js，检查或准备便携版
if (-not $targetNode) {
    $portableNodeDir = Join-Path $ToolsDir "node-v$NodeVersion-win-x64"
    $portableNodeExe = Join-Path $portableNodeDir "node.exe"
    
    if (-not (Test-Path $portableNodeExe)) {
        Write-Host "正在准备独立的 Node.js v$NodeVersion 便携环境到 .tools/ 目录..." -ForegroundColor Yellow
        if (-not (Test-Path $ToolsDir)) {
            New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
        }
        
        $nodeZip = Join-Path $ToolsDir "node-v$NodeVersion-win-x64.zip"
        $downloadUrls = @(
            "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip",
            "https://npmmirror.com/mirrors/node/v$NodeVersion/node-v$NodeVersion-win-x64.zip"
        )
        
        $downloadSuccess = $false
        foreach ($url in $downloadUrls) {
            try {
                Write-Host "正在从 $url 下载 Node.js..." -ForegroundColor Gray
                Invoke-WebRequest -Uri $url -OutFile $nodeZip -UseBasicParsing
                $downloadSuccess = $true
                break
            } catch {
                Write-Warn "从 $url 下载失败: $_"
            }
        }
        
        if (-not $downloadSuccess) {
            throw "无法自动下载 Node.js v$NodeVersion，请手动安装 Node.js >= 22.19.0 并加入 PATH。"
        }
        
        Write-Host "正在解压缩 Node.js..." -ForegroundColor Gray
        Expand-Archive -Path $nodeZip -DestinationPath $ToolsDir -Force
        Remove-Item -Path $nodeZip -Force -ErrorAction SilentlyContinue
    }
    
    $targetNode = $portableNodeExe
    $nodeDir = Split-Path -Parent $targetNode
    $env:PATH = "$nodeDir;$env:PATH"
    Write-Success "使用便携版 Node.js: $(& $targetNode -v)"
}

# 检查 pnpm
if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    Write-Host "未找到 pnpm 命令，正在安装 pnpm@$PnpmVersion..." -ForegroundColor Yellow
    & npm install -g "pnpm@$PnpmVersion"
    $npmPrefix = (& npm config get prefix).Trim()
    if (Test-Path $npmPrefix) {
        $env:PATH = "$npmPrefix;$env:PATH"
    }
}

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    throw "无法找到或安装 pnpm，请确保 pnpm 已正确安装。"
}
Write-Host "pnpm 版本: $(pnpm -v)" -ForegroundColor Gray

# 配置 npm/pnpm 镜像（若指定）
if (-not [string]::IsNullOrWhiteSpace($Registry)) {
    Write-Host "配置 pnpm 镜像为: $Registry" -ForegroundColor Gray
    pnpm config set registry $Registry
}

# -------------------------------------------------------------
# 步骤 2: 拉取并检出官方上游基线
# -------------------------------------------------------------
Write-Step "2/6 准备上游源码基线 (commit: $BaselineCommit)..."

if ($SkipClone -and (Test-Path $SourceDir)) {
    Write-Host "已指定 -SkipClone，跳过源码拉取。" -ForegroundColor Gray
} else {
    if (-not (Test-Path $SourceDir)) {
        Write-Host "正在克隆上游仓库: $UpstreamRepo..." -ForegroundColor Gray
        git clone $UpstreamRepo $SourceDir
    }
    
    Write-Host "检出基线提交: $BaselineCommit..." -ForegroundColor Gray
    git -C $SourceDir checkout $BaselineCommit
}

# -------------------------------------------------------------
# 步骤 3: 解压并应用定制补丁
# -------------------------------------------------------------
Write-Step "3/6 解压并应用桌面定制补丁..."

$patchZip = Join-Path $RepoRoot "patches/desktop-customizations.patch.zip"
if (-not (Test-Path $patchZip)) {
    throw "未找到补丁文件: $patchZip"
}

$unpackedDir = Join-Path $RepoRoot ".unpacked_patch"
if (Test-Path $unpackedDir) {
    Remove-Item -Path $unpackedDir -Recurse -Force
}

Expand-Archive -Path $patchZip -DestinationPath $unpackedDir -Force
$patchFile = Get-ChildItem -Path $unpackedDir -Recurse -File -Filter "*.patch" |
    Where-Object { -not $_.Name.StartsWith("._") } |
    Select-Object -First 1 -ExpandProperty FullName

if ([string]::IsNullOrWhiteSpace($patchFile)) {
    throw "未在补丁压缩包中找到 .patch 文件。"
}
Write-Host "找到补丁文件: $patchFile" -ForegroundColor Gray

# 测试补丁是否已经应用
$checkResult = git -C $SourceDir apply --check --binary $patchFile 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "应用补丁到源码..." -ForegroundColor Gray
    git -C $SourceDir apply --binary $patchFile
    Write-Success "补丁应用成功！"
} else {
    # 检查是否此前已经打过补丁
    $customConfig = Join-Path $SourceDir "apps/desktop-host/config/desktop.cordis.patch.yml"
    if (Test-Path $customConfig) {
        Write-Host "检测到补丁文件已存在于源码目录中，跳过补丁应用。" -ForegroundColor Yellow
    } else {
        throw "应用补丁失败: $checkResult"
    }
}

# 修正 primary-mode 宿主 tsconfig，避免循环引用 client 端导致 Remote 协议未生成前类型检查失败
$primaryCfg = Join-Path $SourceDir "packages/desktop/primary-mode/tsconfig.json"
if (Test-Path $primaryCfg) {
    $cfg = Get-Content $primaryCfg -Raw | ConvertFrom-Json
    $cfg.references = @(@{ path = "../../../vendor/cordis" })
    $cfg | ConvertTo-Json -Depth 5 | Set-Content $primaryCfg -Encoding utf8
}

# 补充桌面端插件在 tsconfig.client.json 中的完整项目引用（包含宿主与客户端双端，确保 tsdown 打包时 lib/types/index.js 存在）
$clientCfg = Join-Path $SourceDir "tsconfig.client.json"
if (Test-Path $clientCfg) {
    $cfg = Get-Content $clientCfg -Raw | ConvertFrom-Json
    $desktopRefs = @(
        @{ path = "./packages/desktop/primary-mode/tsconfig.json" },
        @{ path = "./packages/desktop/primary-mode/tsconfig.client.json" },
        @{ path = "./packages/desktop/puppy-theme/tsconfig.json" },
        @{ path = "./packages/desktop/puppy-theme/tsconfig.client.json" },
        @{ path = "./packages/desktop/code-workspace/tsconfig.json" },
        @{ path = "./packages/desktop/code-workspace/tsconfig.client.json" },
        @{ path = "./packages/desktop/code-insights/tsconfig.json" },
        @{ path = "./packages/desktop/code-insights/tsconfig.client.json" }
    )
    $filtered = @()
    foreach ($r in $cfg.references) {
        if ($r.path -notmatch 'packages/desktop') {
            $filtered += $r
        }
    }
    $webIdx = -1
    for ($i = 0; $i -lt $filtered.Count; $i++) {
        if ($filtered[$i].path -eq './apps/web') {
            $webIdx = $i
            break
        }
    }
    if ($webIdx -ge 0) {
        $cfg.references = @($filtered[0..($webIdx - 1)]) + $desktopRefs + @($filtered[$webIdx..($filtered.Count - 1)])
    } else {
        $cfg.references = $filtered + $desktopRefs
    }
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $clientCfg -Encoding utf8
}

Remove-Item -Path $unpackedDir -Recurse -Force -ErrorAction SilentlyContinue

# -------------------------------------------------------------
# 步骤 4: 安装依赖与构建协议层
# -------------------------------------------------------------
Write-Step "4/6 安装依赖并预生成 Remote 协议与桌面宿主端..."

Push-Location $SourceDir
try {
    if (-not $SkipInstall) {
        Write-Host "执行 pnpm install..." -ForegroundColor Gray
        pnpm install --frozen-lockfile
    } else {
        Write-Host "已指定 -SkipInstall，跳过依赖安装。" -ForegroundColor Gray
    }

    Write-Host "编译 Typert Remote 协议与 host 依赖..." -ForegroundColor Gray
    pnpm exec tsc -b packages/typert/generator/tsconfig.json
    pnpm run build:lib:host

    Write-Host "预编译桌面插件宿主入口 (lib/types/index.js)..." -ForegroundColor Gray
    pnpm exec tsc -b packages/desktop/primary-mode/tsconfig.json packages/desktop/puppy-theme/tsconfig.json packages/desktop/code-workspace/tsconfig.json packages/desktop/code-insights/tsconfig.json
} finally {
    Pop-Location
}

# -------------------------------------------------------------
# 步骤 5: 打包 Windows x64 安装程序
# -------------------------------------------------------------
Write-Step "5/6 打包 Windows Release 安装程序 (x86_64 / x64)..."

$env:DSH_DESKTOP_ALLOW_UNSIGNED_WINDOWS = "1"
$env:DSH_DESKTOP_APP_ID = "ai.deepseek.harness.desktop"
$env:DSH_DESKTOP_TARGET_PLATFORM = "win32"
$env:DSH_DESKTOP_TARGET_ARCH = "x64"
$env:DOWNLOAD_TEST_ORIGIN = "https://github.com"

Push-Location $SourceDir
try {
    Write-Host "正在执行 pnpm run package:desktop:win:x64 (此步骤可能耗时几分钟)..." -ForegroundColor Yellow
    pnpm run package:desktop:win:x64
} finally {
    Pop-Location
}

# -------------------------------------------------------------
# 步骤 6: 归档安装包与计算哈希
# -------------------------------------------------------------
Write-Step "6/6 归档安装包产物并生成校验和..."

$installer = Get-ChildItem -Path $SourceDir -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '__uninstaller' -and $_.DirectoryName -notmatch 'win-unpacked' -and $_.DirectoryName -match 'artifacts' } |
    Select-Object -First 1

if (-not $installer) {
    throw "未在 $SourceDir 中找到生成的 Windows 安装程序 (.exe)！"
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$destExe = Join-Path $OutputDir "DeepSeek-Harness-win-x64.exe"
Copy-Item -Path $installer.FullName -Destination $destExe -Force

$hash = (Get-FileHash -Path $destExe -Algorithm SHA256).Hash.ToLower()
$hashFile = "$destExe.sha256"
"$hash  DeepSeek-Harness-win-x64.exe" | Out-File -FilePath $hashFile -Encoding ascii

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "构建圆满完成！Windows Release 安装程序已生成：" -ForegroundColor Green
Write-Host "文件位置: $destExe" -ForegroundColor Cyan
Write-Host "文件大小: $([math]::Round($installer.Length / 1MB, 2)) MB" -ForegroundColor Cyan
Write-Host "SHA-256:  $hash" -ForegroundColor Cyan
Write-Host "校验文件: $hashFile" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Green
