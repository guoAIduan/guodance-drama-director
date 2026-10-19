<#
.SYNOPSIS
  检查每段提示词是否包含七块结构、禁用神态词、塑料画质词与合适长度。
.EXAMPLE
  powershell -File .\scripts\lint-prompts.ps1 -Project D:\drama\test-drama
.DESCRIPTION
  提示词文件放在 prompts\*.md，_TEMPLATE.md 会被跳过。
  这是生成前的静态检查，不能替代生成后的画面质检。
#>
param(
    [Parameter(Mandatory=$true)][string]$Project,
    [string]$Dir = "prompts",
    [int]$MinChars = 160,
    [int]$MaxChars = 380
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$projectRoot = (Resolve-Path -LiteralPath $Project).Path
$promptDir = Join-Path $projectRoot $Dir
if (-not (Test-Path -LiteralPath $promptDir)) {
    throw "找不到提示词目录：$promptDir"
}

$files = @(Get-ChildItem -LiteralPath $promptDir -Filter *.md -File | Where-Object { $_.Name -ne "_TEMPLATE.md" } | Sort-Object Name)
if ($files.Count -eq 0) {
    throw "提示词目录没有 md 文件：$promptDir"
}

$banned = @(
    '心头一震','目光一沉','瞳孔一缩','嘴角勾起','嘴角上扬','眉头微蹙',
    '眼神复杂','意味深长','若有所思','淡然一笑','冷冷一笑','噙着泪',
    '咬着唇','攥紧拳头','怒目而视','莞尔','颔首','冷哼一声',
    '瞳孔地震','眼神拉丝','空气凝固','气场全开','眼中闪过一丝',
    '脸上写满','歇斯底里'
)
$required = @('【镜头】','【主体】','【环境】','【光线】','【风格】','【负面】')
$errors = New-Object System.Collections.Generic.List[string]
$warns  = New-Object System.Collections.Generic.List[string]

foreach ($f in $files) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    $body = $text
    $fence = [regex]::Match($text, '(?s)```(.*?)```')
    if ($fence.Success) { $body = $fence.Groups[1].Value }
    $plain = ($body -replace '\s', '')

    foreach ($block in $required) {
        if (-not $text.Contains($block)) {
            $errors.Add("$($f.Name)：缺少 $block")
        }
    }
    if (-not $text.Contains('参考图')) {
        $warns.Add("$($f.Name)：没有提到参考图，角色一致性可能不稳")
    }
    foreach ($w in $banned) {
        if ($text.Contains($w)) {
            $errors.Add("$($f.Name)：含禁用神态词 '$w'")
        }
    }
    if ($text -match '8K|毛孔可见') {
        $warns.Add("$($f.Name)：含 '8K/毛孔可见'，容易产生塑料感")
    }
    if ($plain.Length -lt $MinChars) {
        $warns.Add("$($f.Name)：有效字符 $($plain.Length)，低于 $MinChars，信息可能不足")
    } elseif ($plain.Length -gt $MaxChars) {
        $warns.Add("$($f.Name)：有效字符 $($plain.Length)，高于 $MaxChars，模型可能丢中间信息")
    }
}

Write-Output ("检查文件：$($files.Count)")
Write-Output ("ERROR：$($errors.Count)    WARN：$($warns.Count)")
if ($errors.Count -gt 0) {
    Write-Output ""
    Write-Output "--- 必须修复 ---"
    $errors | Select-Object -First 60 | ForEach-Object { Write-Output "ERROR  $_" }
}
if ($warns.Count -gt 0) {
    Write-Output ""
    Write-Output "--- 建议复核 ---"
    $warns | Select-Object -First 40 | ForEach-Object { Write-Output "WARN   $_" }
}

if ($errors.Count -gt 0) { exit 1 } else { exit 0 }
