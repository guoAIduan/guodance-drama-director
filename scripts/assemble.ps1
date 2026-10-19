<#
.SYNOPSIS
  按 EDL 拼接短剧：统一画幅/帧率、对白铺轨、BGM 闪避、响度归一、输出 broadcast 与 clean。
.EXAMPLE
  powershell -File .\scripts\assemble.ps1 -Project D:\drama\test-drama -DryRun
.EXAMPLE
  powershell -File .\scripts\assemble.ps1 -Project D:\drama\test-drama -Mode both
.DESCRIPTION
  依赖 ffmpeg/ffprobe 在 PATH 中。先用 -DryRun 检查命令，再正式执行。
  不会删除任何源素材；临时文件写在 edit\work 下。
  BGM 与环境声各取 EDL 的第一条，并从 0 铺到片尾；多条音乐请先拼成一条，
  或在剪映/达芬奇里按 start/end 精修。
#>
param(
    [Parameter(Mandatory=$true)][string]$Project,
    [string]$Edl = "edit\edl.json",
    [ValidateSet("broadcast","clean","both")][string]$Mode = "both",
    [switch]$DryRun,
    [switch]$BurnSubs,
    [string]$Lut = "",
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

function Format-Invariant {
    param([double]$Value, [string]$Format = "0.####")
    return $Value.ToString($Format, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Show-Command {
    param([string]$Exe, [string[]]$ArgList)
    $parts = @($Exe)
    foreach ($a in $ArgList) {
        if ($a -match '\s') { $parts += ('"' + $a + '"') } else { $parts += $a }
    }
    return ($parts -join ' ')
}

function Invoke-External {
    param([string]$Exe, [string[]]$ArgList)
    $display = Show-Command -Exe $Exe -ArgList $ArgList
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
if (-not $Edl.Contains(":") -and -not $Edl.StartsWith("\\")) {
    $edlPath = Join-Path $projectRoot $Edl
} else {
    $edlPath = $Edl
}
if (-not (Test-Path -LiteralPath $edlPath)) {
    throw "找不到 EDL：$edlPath"
}

$edlData = Get-Content -LiteralPath $edlPath -Raw -Encoding UTF8 | ConvertFrom-Json
$segments = @($edlData.segments | Where-Object { $_ })
if ($segments.Count -eq 0) {
    throw "EDL 里没有 segments"
}

$fmt = $edlData.format
$w = 1080; $h = 1920; $fps = 30
if ($fmt) {
    if ($fmt.width) { $w = [int]$fmt.width }
    if ($fmt.height) { $h = [int]$fmt.height }
    if ($fmt.fps) { $fps = [double]$fmt.fps }
}

if (-not $DryRun) {
    foreach ($tool in @($Ffmpeg, $Ffprobe)) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "找不到 $tool。请安装 ffmpeg 并加入 PATH，或使用 -DryRun 只生成命令。"
        }
    }
}

$workDir = Join-Path $projectRoot "edit\work"
$deliveryDir = Join-Path $projectRoot "delivery"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
New-Item -ItemType Directory -Path $deliveryDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $projectRoot "qc") -Force | Out-Null

$episode = [string]$edlData.project
if ([string]::IsNullOrWhiteSpace($episode)) { $episode = "EP01" }

$clipList = New-Object System.Collections.Generic.List[string]
$wavList  = New-Object System.Collections.Generic.List[string]
$total = 0.0

foreach ($seg in $segments) {
    $id = [string]$seg.id
    if ([string]::IsNullOrWhiteSpace($id)) { throw "EDL 有 segment 缺少 id" }

    $clipRel = [string]$seg.clip
    if ([string]::IsNullOrWhiteSpace($clipRel)) { throw "段 $id 缺少 clip" }
    $clipPath = if ([System.IO.Path]::IsPathRooted($clipRel)) { $clipRel } else { Join-Path $projectRoot $clipRel }
    if (-not (Test-Path -LiteralPath $clipPath)) {
        throw "段 $id 的素材不存在：$clipPath"
    }

    $inVal = 0.0
    $outVal = 0.0
    $inProp = $seg.PSObject.Properties['in']
    $outProp = $seg.PSObject.Properties['out']
    if ($inProp) { $inVal = [double]$inProp.Value }
    if ($outProp) { $outVal = [double]$outProp.Value }
    if ($outVal -le $inVal) {
        throw "段 $id 的 out ($outVal) 必须大于 in ($inVal)"
    }
    $dur = [Math]::Round($outVal - $inVal, 3)
    $total += $dur

    $normClip = Join-Path $workDir ("{0}_norm.mp4" -f $id)
    $vf = "scale=${w}:${h}:force_original_aspect_ratio=decrease,pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=$fps"
    $clipArgs = @(
        "-y","-hide_banner","-loglevel","error",
        "-ss", (Format-Invariant $inVal), "-t", (Format-Invariant $dur),
        "-i", $clipPath,
        "-an","-vf",$vf,
        "-c:v","libx264","-crf","18","-preset","medium","-pix_fmt","yuv420p",
        $normClip
    )
    Invoke-External -Exe $Ffmpeg -ArgList $clipArgs
    $clipList.Add($normClip)

    $audioRel = [string]$seg.audio
    $audioPath = ""
    if (-not [string]::IsNullOrWhiteSpace($audioRel)) {
        $audioPath = if ([System.IO.Path]::IsPathRooted($audioRel)) { $audioRel } else { Join-Path $projectRoot $audioRel }
    }
    $normWav = Join-Path $workDir ("{0}_audio.wav" -f $id)
    if ($audioPath -and (Test-Path -LiteralPath $audioPath)) {
        $aArgs = @(
            "-y","-hide_banner","-loglevel","error",
            "-i",$audioPath,
            "-af",("apad,atrim=0:{0},aresample=48000" -f (Format-Invariant $dur)),
            "-ac","2","-c:a","pcm_s16le",$normWav
        )
        Invoke-External -Exe $Ffmpeg -ArgList $aArgs
    } else {
        if ($audioPath) { Write-Output "WARN  段 $id 的音频不存在，使用静音：$audioPath" }
        $aArgs = @(
            "-y","-hide_banner","-loglevel","error",
            "-f","lavfi","-i","anullsrc=r=48000:cl=stereo",
            "-t",(Format-Invariant $dur),"-c:a","pcm_s16le",$normWav
        )
        Invoke-External -Exe $Ffmpeg -ArgList $aArgs
    }
    $wavList.Add($normWav)
}

$concatTxt = Join-Path $workDir "concat.txt"
$concatLines = $clipList | ForEach-Object {
    $p = $_.Replace("\","/").Replace("'","'\''")
    "file '$p'"
}
Write-Utf8NoBom -Path $concatTxt -Content (($concatLines -join "`n") + "`n")

$silentVideo = Join-Path $workDir "video_silent.mp4"
Invoke-External -Exe $Ffmpeg -ArgList @(
    "-y","-hide_banner","-loglevel","error",
    "-f","concat","-safe","0","-i",$concatTxt,
    "-c","copy",$silentVideo
)

if (-not [string]::IsNullOrWhiteSpace($Lut)) {
    $lutPath = if ([System.IO.Path]::IsPathRooted($Lut)) { $Lut } else { Join-Path $projectRoot $Lut }
    if (-not (Test-Path -LiteralPath $lutPath)) {
        throw "找不到 LUT：$lutPath"
    }
    $graded = Join-Path $workDir "video_graded.mp4"
    $escapedLut = $lutPath.Replace("\","/").Replace(":","\:")
    Invoke-External -Exe $Ffmpeg -ArgList @(
        "-y","-hide_banner","-loglevel","error",
        "-i",$silentVideo,
        "-vf","lut3d='$escapedLut'",
        "-an","-c:v","libx264","-crf","18","-preset","medium","-pix_fmt","yuv420p",
        $graded
    )
    $silentVideo = $graded
}

$wavTxt = Join-Path $workDir "concat_audio.txt"
$wavLines = $wavList | ForEach-Object {
    $p = $_.Replace("\","/").Replace("'","'\''")
    "file '$p'"
}
Write-Utf8NoBom -Path $wavTxt -Content (($wavLines -join "`n") + "`n")

$dialogueWav = Join-Path $workDir "dialogue.wav"
Invoke-External -Exe $Ffmpeg -ArgList @(
    "-y","-hide_banner","-loglevel","error",
    "-f","concat","-safe","0","-i",$wavTxt,
    "-c:a","pcm_s16le",$dialogueWav
)

function Get-GainLinear {
    param($Value, [double]$DefaultDb)
    $db = $DefaultDb
    if ($null -ne $Value) {
        $parsed = 0.0
        if ([double]::TryParse([string]$Value, [ref]$parsed)) { $db = $parsed }
    }
    return [Math]::Pow(10, $db / 20.0)
}

$amb = @($edlData.ambience | Where-Object { $_ -and $_.file }) | Select-Object -First 1
$bgm = @($edlData.bgm | Where-Object { $_ -and $_.file }) | Select-Object -First 1
$ambPath = ""
$bgmPath = ""
$hasAmb = $false
$hasBgm = $false
if ($amb) {
    $ambPath = if ([System.IO.Path]::IsPathRooted([string]$amb.file)) { [string]$amb.file } else { Join-Path $projectRoot ([string]$amb.file) }
    $hasAmb = Test-Path -LiteralPath $ambPath
    if (-not $hasAmb) { Write-Output "WARN  环境声不存在：$ambPath" }
}
if ($bgm) {
    $bgmPath = if ([System.IO.Path]::IsPathRooted([string]$bgm.file)) { [string]$bgm.file } else { Join-Path $projectRoot ([string]$bgm.file) }
    $hasBgm = Test-Path -LiteralPath $bgmPath
    if (-not $hasBgm) { Write-Output "WARN  BGM 不存在：$bgmPath" }
}

$totalText = Format-Invariant $total
$outputs = @()

if ($Mode -eq "clean" -or $Mode -eq "both") {
    $cleanOut = Join-Path $deliveryDir ("{0}_clean.mp4" -f $episode)
    $cleanArgs = @(
        "-y","-hide_banner","-loglevel","error",
        "-i",$silentVideo,"-i",$dialogueWav,
        "-map","0:v:0","-map","1:a:0",
        "-c:v","copy","-c:a","aac","-b:a","192k","-ar","48000",
        "-af","loudnorm=I=-14:TP=-1.5:LRA=11",
        "-t",$totalText,"-movflags","+faststart",$cleanOut
    )
    Invoke-External -Exe $Ffmpeg -ArgList $cleanArgs
    $outputs += $cleanOut
}

if ($Mode -eq "broadcast" -or $Mode -eq "both") {
    $broadcastOut = Join-Path $deliveryDir ("{0}_broadcast.mp4" -f $episode)
    $inputArgs = @("-y","-hide_banner","-loglevel","error","-i",$silentVideo,"-i",$dialogueWav)
    $filterParts = New-Object System.Collections.Generic.List[string]
    $filterParts.Add("[1:a]highpass=f=80,lowpass=f=12000,acompressor=threshold=-18dB:ratio=3:attack=5:release=120[dlg]")

    $mixLabels = @()
    $dlgMix = "[dlg]"
    if ($hasBgm) {
        $filterParts.Add("[dlg]asplit=2[dlg_mix][dlg_key]")
        $dlgMix = "[dlg_mix]"
    }
    $mixLabels += $dlgMix
    $nextInput = 2

    if ($hasAmb) {
        $inputArgs += @("-i", $ambPath)
        $ambGain = Format-Invariant (Get-GainLinear $amb.gain_db -26)
        $filterParts.Add("[${nextInput}:a]volume=$ambGain[amb]")
        $mixLabels += "[amb]"
        $nextInput++
    }

    if ($hasBgm) {
        $inputArgs += @("-i", $bgmPath)
        $bgmGain = Format-Invariant (Get-GainLinear $bgm.gain_db -18)
        $filterParts.Add("[${nextInput}:a]volume=$bgmGain[bg]")
        $filterParts.Add("[bg][dlg_key]sidechaincompress=threshold=0.03:ratio=8:attack=5:release=250[bgduck]")
        $mixLabels += "[bgduck]"
        $nextInput++
    }

    if ($mixLabels.Count -gt 1) {
        $amix = ($mixLabels -join "") + ("amix=inputs={0}:duration=first:dropout_transition=0,loudnorm=I=-14:TP=-1.5:LRA=11[aout]" -f $mixLabels.Count)
        $filterParts.Add($amix)
    } else {
        $filterParts.Add("$dlgMix" + "loudnorm=I=-14:TP=-1.5:LRA=11[aout]")
    }

    $filter = $filterParts -join ";"
    $mixArgs = $inputArgs + @(
        "-filter_complex",$filter,
        "-map","0:v:0","-map","[aout]",
        "-c:v","copy","-c:a","aac","-b:a","192k","-ar","48000",
        "-t",$totalText,"-movflags","+faststart",$broadcastOut
    )
    Invoke-External -Exe $Ffmpeg -ArgList $mixArgs
    $outputs += $broadcastOut
}

if ($BurnSubs) {
    $subRel = [string]$edlData.subtitles
    if (-not [string]::IsNullOrWhiteSpace($subRel)) {
        $subPath = if ([System.IO.Path]::IsPathRooted($subRel)) { $subRel } else { Join-Path $projectRoot $subRel }
        if (Test-Path -LiteralPath $subPath) {
            foreach ($out in @($outputs)) {
                $burned = [System.IO.Path]::ChangeExtension($out, ".sub.mp4")
                $escaped = $subPath.Replace("\","/").Replace(":","\:")
                Invoke-External -Exe $Ffmpeg -ArgList @(
                    "-y","-hide_banner","-loglevel","error",
                    "-i",$out,
                    "-vf","subtitles='$escaped'",
                    "-c:v","libx264","-crf","20","-preset","medium",
                    "-c:a","copy","-movflags","+faststart",$burned
                )
                $outputs += $burned
            }
        } else {
            Write-Output "WARN  字幕不存在，跳过烧录：$subPath"
        }
    }
}

if (-not $DryRun) {
    $report = @()
    foreach ($out in @($outputs | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $out) {
            $info = & $Ffprobe -v error -show_entries "format=duration,size:stream=codec_name,width,height,r_frame_rate" -of json $out | Out-String
            $report += [pscustomobject]@{ file = $out; probe = ($info | ConvertFrom-Json) }
        }
    }
    Write-Utf8NoBom -Path (Join-Path $projectRoot "qc\assemble-report.json") -Content ($report | ConvertTo-Json -Depth 8)
}

Write-Output ""
Write-Output "拼接完成：$($segments.Count) 段，总时长 ${total}s"
if ($DryRun) { Write-Output "以上为 dry-run 计划，未实际写入文件。" }
foreach ($out in ($outputs | Select-Object -Unique)) {
    Write-Output "输出：$out"
}
