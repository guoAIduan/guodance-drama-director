<#
.SYNOPSIS
  为每个镜头段生成 3×2 接触表、技术参数表，并可比对相邻段首尾帧。
.EXAMPLE
  powershell -File .\scripts\qc-sheet.ps1 -Project D:\drama\test-drama -DryRun
.EXAMPLE
  powershell -File .\scripts\qc-sheet.ps1 -Project D:\drama\test-drama -Pairs D01:D02,D02:D03
.DESCRIPTION
  依赖 ffmpeg/ffprobe。输出 qc\contact_sheets 与 qc\technical.csv。
#>
param(
    [Parameter(Mandatory=$true)][string]$Project,
    [string]$ClipsDir = "clips",
    [string]$OutDir = "qc\contact_sheets",
    [string[]]$Pairs = @(),
    [switch]$DryRun,
    [string]$Ffmpeg = "ffmpeg",
    [string]$Ffprobe = "ffprobe"
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Invoke-External {
    param([string]$Exe, [string[]]$ArgList)
    $display = $Exe + " " + (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " ")
    if ($DryRun) {
        Write-Output "[dry-run] $display"
        return
    }
    & $Exe @ArgList
    if ($LASTEXITCODE -ne 0) {
        throw "命令失败（exit $LASTEXITCODE）：$display"
    }
}

$projectRoot = (Resolve-Path -LiteralPath $Project).Path
$clipsPath = Join-Path $projectRoot $ClipsDir
$outPath = Join-Path $projectRoot $OutDir
if (-not (Test-Path -LiteralPath $clipsPath)) {
    throw "找不到素材目录：$clipsPath"
}
New-Item -ItemType Directory -Path $outPath -Force | Out-Null

if (-not $DryRun) {
    foreach ($tool in @($Ffmpeg, $Ffprobe)) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "找不到 $tool。请安装 ffmpeg 并加入 PATH，或使用 -DryRun。"
        }
    }
}

$clips = @(Get-ChildItem -LiteralPath $clipsPath -Filter *.mp4 -File | Sort-Object Name)
if ($clips.Count -eq 0) {
    throw "素材目录没有 mp4：$clipsPath"
}

$clipMap = @{}
$edlPath = Join-Path $projectRoot "edit\edl.json"
if (Test-Path -LiteralPath $edlPath) {
    $edlData = Get-Content -LiteralPath $edlPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($s in @($edlData.segments)) {
        if ($s -and $s.id -and $s.clip) {
            $rel = [string]$s.clip
            $abs = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $projectRoot $rel }
            $clipMap[[string]$s.id] = $abs
        }
    }
}

$rows = @()
foreach ($clip in $clips) {
    $sheet = Join-Path $outPath ($clip.BaseName + "_sheet.jpg")
    Invoke-External -Exe $Ffmpeg -ArgList @(
        "-y","-hide_banner","-loglevel","error",
        "-i",$clip.FullName,
        "-vf","fps=1,scale=360:-1,tile=3x2",
        "-frames:v","1",$sheet
    )

    if (-not $DryRun) {
        $probeJson = & $Ffprobe -v error -show_entries "format=duration,size:stream=codec_type,codec_name,width,height,r_frame_rate" -of json $clip.FullName | Out-String
        $probe = $probeJson | ConvertFrom-Json
        $video = @($probe.streams | Where-Object { $_.codec_type -eq "video" }) | Select-Object -First 1
        $audio = @($probe.streams | Where-Object { $_.codec_type -eq "audio" }) | Select-Object -First 1
        $rows += [pscustomobject]@{
            file = $clip.Name
            duration = [Math]::Round([double]$probe.format.duration, 2)
            width = if ($video) { $video.width } else { "" }
            height = if ($video) { $video.height } else { "" }
            fps = if ($video) { $video.r_frame_rate } else { "" }
            video_codec = if ($video) { $video.codec_name } else { "" }
            audio_codec = if ($audio) { $audio.codec_name } else { "none" }
            sheet = $sheet
        }
    } else {
        $rows += [pscustomobject]@{ file = $clip.Name; duration = ""; width = ""; height = ""; fps = ""; video_codec = ""; audio_codec = ""; sheet = $sheet }
    }
}

if (-not $DryRun) {
    $csv = $rows | ConvertTo-Csv -NoTypeInformation
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines((Join-Path $projectRoot "qc\technical.csv"), $csv, $enc)
}

foreach ($pair in $Pairs) {
    $parts = $pair -split ':'
    if ($parts.Count -ne 2) {
        Write-Output "WARN  跳过无效 Pairs 项：$pair"
        continue
    }
    $a = if ($clipMap.ContainsKey($parts[0])) { $clipMap[$parts[0]] } else { Join-Path $clipsPath ($parts[0] + ".mp4") }
    $b = if ($clipMap.ContainsKey($parts[1])) { $clipMap[$parts[1]] } else { Join-Path $clipsPath ($parts[1] + ".mp4") }
    if (-not (Test-Path -LiteralPath $a) -or -not (Test-Path -LiteralPath $b)) {
        Write-Output "WARN  找不到相邻段：$pair"
        continue
    }
    $last = Join-Path $outPath ($parts[0] + "_last.jpg")
    $first = Join-Path $outPath ($parts[1] + "_first.jpg")
    Invoke-External -Exe $Ffmpeg -ArgList @("-y","-hide_banner","-loglevel","error","-sseof","-0.2","-i",$a,"-frames:v","1",$last)
    Invoke-External -Exe $Ffmpeg -ArgList @("-y","-hide_banner","-loglevel","error","-i",$b,"-frames:v","1",$first)
    if (-not $DryRun) {
        $ssimOut = & $Ffmpeg -hide_banner -i $last -i $first -lavfi ssim -f null - 2>&1 | Out-String
        $m = [regex]::Match($ssimOut, "All:([0-9\.]+)")
        if ($m.Success) {
            Write-Output ("{0} -> {1}  首尾帧 SSIM: {2}" -f $parts[0], $parts[1], $m.Groups[1].Value)
        } else {
            Write-Output ("{0} -> {1}  SSIM 未解析，查看输出" -f $parts[0], $parts[1])
        }
    }
}

Write-Output ""
Write-Output "接触表目录：$outPath"
Write-Output "素材数：$($clips.Count)"
if ($DryRun) { Write-Output "以上为 dry-run 计划，未实际写入文件。" }
if (-not $DryRun) {
    Write-Output "技术参数表：$(Join-Path $projectRoot 'qc\technical.csv')"
}
