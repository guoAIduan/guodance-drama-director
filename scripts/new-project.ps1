<#
.SYNOPSIS
  从模板创建一个短剧生产项目目录。
.EXAMPLE
  powershell -File .\scripts\new-project.ps1 -Title "祠堂" -Root "D:\drama" -Episode EP01 -TargetSeconds 90
.DESCRIPTION
  生成 production 目录、复制模板、替换占位符。已存在的目录不会被覆盖。
#>
param(
    [Parameter(Mandatory=$true)][string]$Title,
    [string]$Root = ".",
    [string]$Episode = "EP01",
    [double]$TargetSeconds = 90,
    [string]$Slug = ""
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Write-Utf8Bom {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$templateRoot = Join-Path $skillRoot "assets\templates"
if (-not (Test-Path -LiteralPath $templateRoot)) {
    throw "找不到模板目录：$templateRoot"
}

if ([string]::IsNullOrWhiteSpace($Slug)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Slug = "drama-$stamp"
}
if ($Slug -notmatch '^[a-z0-9][a-z0-9-]{0,48}$') {
    throw "Slug 只能用小写字母、数字和连字符，且不能以连字符开头：$Slug"
}
if ($Episode -notmatch '^[A-Za-z0-9_-]{1,20}$') {
    throw "Episode 只能用字母、数字、下划线或连字符：$Episode"
}
if ($TargetSeconds -le 0 -or $TargetSeconds -gt 600) {
    throw "TargetSeconds 必须在 1–600 之间：$TargetSeconds"
}

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$projectRoot = Join-Path $rootPath $Slug
if (Test-Path -LiteralPath $projectRoot) {
    throw "目录已存在，不覆盖：$projectRoot"
}

$dirs = @(
    "assets\characters",
    "assets\scenes",
    "assets\props",
    "clips",
    "prompts",
    "audio\lines",
    "audio\segments",
    "audio\ambience",
    "audio\bgm",
    "audio\sfx",
    "qc\contact_sheets",
    "edit",
    "looks",
    "delivery"
)

New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
foreach ($d in $dirs) {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot $d) -Force | Out-Null
}

$map = @(
    @{ Template = "brief.md";           Target = "brief.md" },
    @{ Template = "bible.md";           Target = "bible.md" },
    @{ Template = "shotlist.csv";       Target = "shotlist.csv" },
    @{ Template = "edl.json";           Target = "edit\edl.json" },
    @{ Template = "voice-plan.csv";     Target = "audio\voice-plan.csv" },
    @{ Template = "qc-report.md";       Target = "qc\report.md" },
    @{ Template = "publish.md";         Target = "delivery\publish.md" },
    @{ Template = "state.json";         Target = "state.json" },
    @{ Template = "prompt-segment.md";  Target = "prompts\_TEMPLATE.md" },
    @{ Template = "model-profile.md";   Target = "model-profile.md" }
)

foreach ($item in $map) {
    $src = Join-Path $templateRoot $item.Template
    $dst = Join-Path $projectRoot $item.Target
    if (-not (Test-Path -LiteralPath $src)) {
        throw "模板缺失：$src"
    }
    $text = Get-Content -LiteralPath $src -Raw -Encoding UTF8
    $text = $text.Replace("{{TITLE}}", $Title)
    $text = $text.Replace("{{EPISODE}}", $Episode)
    $text = $text.Replace("{{TARGET_SECONDS}}", ([string]$TargetSeconds))
    $text = $text.Replace("{{LOGLINE}}", "（一句话卖点待填写）")
    if ($item.Target -like "*.csv") {
        Write-Utf8Bom -Path $dst -Content $text
    } else {
        Write-Utf8NoBom -Path $dst -Content $text
    }
}

$scriptStub = @"
# $Title · $Episode 可拍分场稿

（在此写入剧本体检结果、P0/P1 修改清单与分场稿。）
"@
Write-Utf8NoBom -Path (Join-Path $projectRoot "script.md") -Content $scriptStub

$manifest = @"
{
  "characters": [],
  "scenes": [],
  "props": []
}
"@
Write-Utf8NoBom -Path (Join-Path $projectRoot "assets\manifest.json") -Content $manifest

Write-Output "项目已创建：$projectRoot"
Write-Output "集数：$Episode    目标时长：$TargetSeconds 秒"
Write-Output "提示：shotlist.csv 目前是字段示例，写真实分镜时整体替换。"
Write-Output ""
Write-Output "下一步："
Write-Output "  1. 填 brief.md / script.md"
Write-Output "  2. 填 model-profile.md（探测模型能力）"
Write-Output "  3. 写 shotlist.csv 后运行："
Write-Output "     powershell -File `"$PSScriptRoot\validate-shotlist.ps1`" -Path `"$projectRoot\shotlist.csv`" -TargetSeconds $TargetSeconds"
