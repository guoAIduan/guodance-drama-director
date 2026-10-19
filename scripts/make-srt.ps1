<#
.SYNOPSIS
  从 voice-plan.csv 与 EDL 生成中文 SRT 字幕。
.EXAMPLE
  powershell -File .\scripts\make-srt.ps1 -Project D:\drama\test-drama
.DESCRIPTION
  voice-plan.csv 的 start/end 是段内相对时间；脚本按 EDL 段顺序累加成全局时间。
  每行最多 12 个汉字，每条最多 2 行；超长台词按字数比例拆成多条。
#>
param(
    [Parameter(Mandatory=$true)][string]$Project,
    [string]$LinesCsv = "audio\voice-plan.csv",
    [string]$Edl = "edit\edl.json",
    [string]$Out = "",
    [int]$MaxCharsPerLine = 12,
    [double]$CharsPerSecond = 4.2
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Write-Utf8Bom {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Format-SrtTime {
    param([double]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    $ms = [int][Math]::Round($Seconds * 1000)
    $h = [int][Math]::Floor($ms / 3600000)
    $ms = $ms % 3600000
    $m = [int][Math]::Floor($ms / 60000)
    $ms = $ms % 60000
    $s = [int][Math]::Floor($ms / 1000)
    $f = $ms % 1000
    return "{0:00}:{1:00}:{2:00},{3:000}" -f $h, $m, $s, $f
}

function Split-SubtitleCues {
    param([string]$Text, [int]$MaxChars)
    $clean = ($Text -replace '[\r\n]+', ' ').Trim()
    $clean = $clean.TrimEnd('。', '，', '；', '：', '、')
    if ([string]::IsNullOrWhiteSpace($clean)) { return @() }

    $parts = @([regex]::Split($clean, '(?<=[，。！？；：])') | Where-Object { $_ -and $_.Trim().Length -gt 0 })
    $chunks = New-Object System.Collections.Generic.List[string]
    foreach ($p in $parts) {
        $t = $p.Trim()
        if ($t.Length -le $MaxChars) {
            $chunks.Add($t)
        } else {
            for ($i = 0; $i -lt $t.Length; $i += $MaxChars) {
                $len = [Math]::Min($MaxChars, $t.Length - $i)
                $chunks.Add($t.Substring($i, $len))
            }
        }
    }

    $cues = New-Object System.Collections.Generic.List[string]
    $current = ""
    foreach ($c in $chunks) {
        if ([string]::IsNullOrEmpty($current)) {
            $current = $c
        } elseif (($current.Length + $c.Length) -le ($MaxChars * 2)) {
            $current += $c
        } else {
            $cues.Add($current)
            $current = $c
        }
    }
    if ($current) { $cues.Add($current) }
    return $cues
}

$projectRoot = (Resolve-Path -LiteralPath $Project).Path
$linesPath = Join-Path $projectRoot $LinesCsv
$edlPath = Join-Path $projectRoot $Edl
if (-not (Test-Path -LiteralPath $linesPath)) { throw "找不到配音表：$linesPath" }
if (-not (Test-Path -LiteralPath $edlPath)) { throw "找不到 EDL：$edlPath" }

$lines = @(Import-Csv -LiteralPath $linesPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_.text) })
if ($lines.Count -eq 0) { throw "配音表没有台词：$linesPath" }

$edlData = Get-Content -LiteralPath $edlPath -Raw -Encoding UTF8 | ConvertFrom-Json
$offsetMap = @{}
$cursor = 0.0
$episode = [string]$edlData.project
foreach ($seg in @($edlData.segments)) {
    if (-not $seg) { continue }
    $id = [string]$seg.id
    $offsetMap[$id] = $cursor
    $inVal = 0.0
    $outVal = 0.0
    $inProp = $seg.PSObject.Properties['in']
    $outProp = $seg.PSObject.Properties['out']
    if ($inProp) { $inVal = [double]$inProp.Value }
    if ($outProp) { $outVal = [double]$outProp.Value }
    if ($outVal -gt $inVal) { $cursor += ($outVal - $inVal) }
}

if ([string]::IsNullOrWhiteSpace($Out)) {
    if ([string]::IsNullOrWhiteSpace($episode)) { $episode = "EP01" }
    $Out = Join-Path $projectRoot ("delivery\{0}.srt" -f $episode)
} elseif (-not [System.IO.Path]::IsPathRooted($Out)) {
    $Out = Join-Path $projectRoot $Out
}
$outDir = Split-Path -Parent $Out
if ($outDir) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$entries = New-Object System.Collections.Generic.List[string]
$index = 1

foreach ($line in $lines) {
    $segId = [string]$line.segment_id
    if (-not $offsetMap.ContainsKey($segId)) {
        Write-Output "WARN  台词 $($line.line_id) 的 segment_id '$segId' 不在 EDL 中，跳过"
        continue
    }
    $offset = [double]$offsetMap[$segId]
    $start = 0.0
    $end = 0.0
    if (-not [double]::TryParse([string]$line.start, [ref]$start)) { $start = 0.0 }
    $textLen = ([string]$line.text).Length
    if (-not [double]::TryParse([string]$line.end, [ref]$end) -or $end -le $start) {
        $end = $start + [Math]::Max(0.8, $textLen / $CharsPerSecond)
    }
    if ($end -le $start) { $end = $start + 0.8 }

    $cues = @(Split-SubtitleCues -Text ([string]$line.text) -MaxChars $MaxCharsPerLine)
    if ($cues.Count -eq 0) { continue }
    $totalChars = 0
    foreach ($c in $cues) { $totalChars += $c.Length }
    if ($totalChars -le 0) { continue }

    $span = $end - $start
    $t = $start
    foreach ($cue in $cues) {
        $share = $cue.Length / $totalChars
        $cueDur = [Math]::Max(0.4, $span * $share)
        $cueEnd = [Math]::Min($end, $t + $cueDur)
        if ($cueEnd -le $t) { $cueEnd = $t + 0.4 }

        $line1 = $cue
        $line2 = ""
        if ($cue.Length -gt $MaxCharsPerLine) {
            $line1 = $cue.Substring(0, $MaxCharsPerLine)
            $line2 = $cue.Substring($MaxCharsPerLine)
        }
        $textOut = if ($line2) { "$line1`n$line2" } else { $line1 }

        $entries.Add([string]$index)
        $entries.Add((Format-SrtTime ($offset + $t)) + " --> " + (Format-SrtTime ($offset + $cueEnd)))
        $entries.Add($textOut)
        $entries.Add("")
        $index++
        $t = $cueEnd
    }
}

if ($entries.Count -eq 0) { throw "没有生成任何字幕条目" }
Write-Utf8Bom -Path $Out -Content (($entries -join "`r`n") + "`r`n")
Write-Output "字幕已生成：$Out"
Write-Output "条目：$($index - 1)    总时长：$([Math]::Round($cursor, 1))s"
