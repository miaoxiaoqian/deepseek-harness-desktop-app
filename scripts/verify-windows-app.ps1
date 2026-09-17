<#
.SYNOPSIS
    DeepSeek Harness Desktop Windows 安装包校验脚本

.DESCRIPTION
    计算指定 Windows 安装包文件的 SHA-256 哈希值，并与记录的校验和进行比对。

.PARAMETER FilePath
    待校验的安装包路径，默认为 release/DeepSeek-Harness-win-x64.exe

.PARAMETER ChecksumFile
    存储期望哈希值的文件路径，默认为 release/DeepSeek-Harness-win-x64.exe.sha256
#>

[CmdletBinding()]
param (
    [string]$FilePath = "",
    [string]$ChecksumFile = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($FilePath)) {
    $FilePath = Join-Path $RepoRoot "release/DeepSeek-Harness-win-x64.exe"
}
if ([string]::IsNullOrWhiteSpace($ChecksumFile)) {
    $ChecksumFile = "$FilePath.sha256"
}

if (-not (Test-Path $FilePath)) {
    Write-Error "找不到待校验的文件: $FilePath"
    exit 1
}

Write-Host "正在计算文件 SHA-256 哈希: $FilePath ..." -ForegroundColor Gray
$actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLower()
Write-Host "实际哈希值: $actualHash" -ForegroundColor Cyan

if (Test-Path $ChecksumFile) {
    $rawExpected = (Get-Content -Path $ChecksumFile -Raw).Trim()
    $expectedHash = ($rawExpected -split '\s+')[0].ToLower()
    Write-Host "预期哈希值: $expectedHash" -ForegroundColor Cyan
    
    if ($actualHash -eq $expectedHash) {
        Write-Host "`n[PASS] 哈希校验完全匹配！该安装包完整无损且未被篡改。" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`n[FAIL] 哈希校验不匹配！安装包可能损坏或被修改。" -ForegroundColor Red
        exit 2
    }
} else {
    Write-Host "`n[INFO] 未找到参考校验文件 ($ChecksumFile)，请将上述实际哈希值与官方发布的校验码进行核对。" -ForegroundColor Yellow
}
