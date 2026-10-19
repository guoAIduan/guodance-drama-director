<#
.SYNOPSIS
  校验短剧分镜表：字段、时长、段长、台词、可生成性、禁用词、参考图、钩子覆盖。
.EXAMPLE
  powershell -File .\scripts\validate-shotlist.ps1 -Path .\shotlist.csv -TargetSeconds 90
.EXAMPLE
  powershell -File .\scripts\validate-shotlist.ps1 -Path .\shotlist.csv -TargetSeconds 0
.DESCRIPTION
  本脚本是分镜表结构口径的唯一执行标准。文档与脚本冲突时，以脚本为准。
  -TargetSeconds 0 表示跳过整集时长校验，适合校验片段或模板。
#>
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [double]$TargetSeconds = 90,
    [double]$ToleranceSeconds = 8,
    [double]$MaxSegmentSeconds = 12,
    [double]$MinSegmentSeconds = 3,
    [int]$DialogueWarnChars = 12,
    [int]$DialogueMaxChars = 18,
    [double]$CharsPerSecond = 4.2,
    [int]$GenerabilityWarn = 70,
    [int]$GenerabilityMin = 60,
    [int]$MaxShotsPerSegment = 3
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if (-not (Test-Path -LiteralPath $Path)) {
    throw "找不到分镜表：$Path"
}

$rows = @(Import-Csv -LiteralPath $Path -Encoding UTF8 | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.'镜号')
})
if ($rows.Count -eq 0) {
    throw "分镜表没有数据行：$Path"
}

$headers = @($rows[0].PSObject.Properties.Name)
$required = @(
    '场次','段号','镜号','时长(秒)','景别','运镜','构图','画面内容',
    '表演指导','场景','时间','光影','标记','可生成性','参考图'
)
$errors = New-Object System.Collections.Generic.List[string]
$warns  = New-Object System.Collections.Generic.List[string]

foreach ($c in $required) {
    if ($headers -notcontains $c) {
        $errors.Add("缺少必填列：$c")
    }
}
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Output "ERROR  $_" }
    Write-Output ""
    Write-Output "当前列：$($headers -join ', ')"
    exit 1
}

$banned = @(
    '心头一震','目光一沉','瞳孔一缩','嘴角勾起','嘴角上扬','眉头微蹙',
    '眼神复杂','意味深长','若有所思','淡然一笑','冷冷一笑','噙着泪',
    '咬着唇','攥紧拳头','怒目而视','莞尔','颔首','冷哼一声',
    '瞳孔地震','眼神拉丝','空气凝固','气场全开','眼中闪过一丝',
    '脸上写满','歇斯底里'
)
$allowedFlags = @('普通','钩子','反转','情绪最高点','结尾悬念')

$seenShots = @{}
$totalDuration = 0.0
$sceneDuration = @{}
$segmentRows = @{}
$flagCount = @{}

foreach ($r in $rows) {
    $scene = [string]$r.'场次'
    $seg   = [string]$r.'段号'
    $shot  = [string]$r.'镜号'
    $label = "$scene/$seg/$shot"

    if ($scene -notmatch '^S\d{2,}$') { $warns.Add("$label：场次建议用 S01 格式") }
    if ($seg -notmatch '^D\d{2,}$')   { $warns.Add("$label：段号建议用 D01 格式") }
    if ($shot -notmatch '^S\d{2,}-\d{2,}$') { $warns.Add("$label：镜号建议用 S01-01 格式") }
    if ($seenShots.ContainsKey($shot)) {
        $errors.Add("$label：镜号重复")
    } else {
        $seenShots[$shot] = $true
    }

    $dur = 0.0
    $durText = ([string]$r.'时长(秒)') -replace '[^\d\.]', ''
    if (-not [double]::TryParse($durText, [ref]$dur) -or $dur -le 0) {
        $errors.Add("$label：时长(秒) 缺失或非数字")
        $dur = 0.0
    } elseif ($dur -lt 1.0 -or $dur -gt 15.0) {
        $warns.Add("$label：单镜时长 ${dur}s 超出 1–15s 常规范围")
    }
    $totalDuration += $dur
    if (-not $sceneDuration.ContainsKey($scene)) { $sceneDuration[$scene] = 0.0 }
    $sceneDuration[$scene] += $dur

    if (-not $segmentRows.ContainsKey($seg)) {
        $segmentRows[$seg] = New-Object System.Collections.Generic.List[object]
    }
    $segmentRows[$seg].Add($r)

    foreach ($f in @('景别','运镜','构图','画面内容','表演指导','场景','时间','光影','参考图')) {
        if ([string]::IsNullOrWhiteSpace([string]$r.$f)) {
            $errors.Add("$label：'$f' 为空")
        }
    }

    $flag = ([string]$r.'标记') -replace '🔴', ''
    $flag = $flag.Trim()
    if ([string]::IsNullOrWhiteSpace($flag)) {
        $errors.Add("$label：'标记' 为空")
    } elseif ($allowedFlags -notcontains $flag) {
        $warns.Add("$label：标记 '$flag' 不在标准值（普通/钩子/反转/情绪最高点/结尾悬念）")
    } else {
        if (-not $flagCount.ContainsKey($flag)) { $flagCount[$flag] = 0 }
        $flagCount[$flag]++
    }

    $gen = 0
    $genText = ([string]$r.'可生成性') -replace '[^\d]', ''
    if ([string]::IsNullOrWhiteSpace($genText) -or -not [int]::TryParse($genText, [ref]$gen)) {
        $errors.Add("$label：可生成性 缺失或非数字")
    } elseif ($gen -lt $GenerabilityMin) {
        $errors.Add("$label：可生成性 $gen < $GenerabilityMin，必须改写分镜")
    } elseif ($gen -lt $GenerabilityWarn) {
        $warns.Add("$label：可生成性 $gen 偏低，建议简化")
    }

    $perf = [string]$r.'表演指导'
    foreach ($w in $banned) {
        if ($perf.Contains($w)) {
            $errors.Add("$label：表演指导含禁用神态词 '$w'")
        }
    }

    $line = [string]$r.'台词'
    $speaker = [string]$r.'说话人'
    if (-not [string]::IsNullOrWhiteSpace($line)) {
        if ([string]::IsNullOrWhiteSpace($speaker)) {
            $errors.Add("$label：有台词但说话人为空")
        }
        $parts = @($line -split '[。！？!?，,；;]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach ($p in $parts) {
            $clean = ($p -replace '[\s“”"'']', '')
            $len = $clean.Length
            if ($len -gt $DialogueMaxChars) {
                $errors.Add("$label：台词单句 ${len} 字，超过上限 $DialogueMaxChars，需拆句")
            } elseif ($len -gt $DialogueWarnChars) {
                $warns.Add("$label：台词单句 ${len} 字，建议压到 $DialogueWarnChars 字内")
            }
        }
        $cleanAll = ($line -replace '[\s“”"'']', '')
        $speechSeconds = [Math]::Round($cleanAll.Length / $CharsPerSecond, 1)
        if ($dur -gt 0 -and $speechSeconds -gt ($dur + 0.6)) {
            $errors.Add("$label：台词约 ${speechSeconds}s，镜头 ${dur}s，明显说不完")
        } elseif ($dur -gt 0 -and $speechSeconds -gt $dur) {
            $warns.Add("$label：台词约 ${speechSeconds}s，镜头 ${dur}s，建议加时长或拆句")
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($speaker)) {
        $warns.Add("$label：有说话人但无台词")
    }
}

foreach ($seg in $segmentRows.Keys) {
    $items = $segmentRows[$seg]
    $sum = 0.0
    $scenes = @{}
    foreach ($it in $items) {
        $v = ([string]$it.'时长(秒)') -replace '[^\d\.]', ''
        $d = 0.0
        if ([double]::TryParse($v, [ref]$d)) { $sum += $d }
        $scenes[[string]$it.'场次'] = $true
    }
    if ($scenes.Count -gt 1) {
        $errors.Add("段 $seg：跨场次（$($scenes.Keys -join ',')），必须拆段")
    }
    if ($sum -gt $MaxSegmentSeconds) {
        $errors.Add("段 $seg：总时长 ${sum}s 超过单次生成上限 ${MaxSegmentSeconds}s")
    }
    if ($sum -lt $MinSegmentSeconds) {
        $warns.Add("段 $seg：总时长 ${sum}s 低于 ${MinSegmentSeconds}s，建议合并或加反应")
    }
    if ($items.Count -gt $MaxShotsPerSegment) {
        $warns.Add("段 $seg：$($items.Count) 个镜头，超过建议的 $MaxShotsPerSegment 个")
    }
}

foreach ($g in ($rows | Group-Object { [string]$_.'场次' })) {
    $nums = @()
    foreach ($it in $g.Group) {
        $m = [regex]::Match([string]$it.'镜号', '-(\d+)$')
        if ($m.Success) { $nums += [int]$m.Groups[1].Value }
    }
    $nums = @($nums | Sort-Object)
    for ($i = 0; $i -lt $nums.Count; $i++) {
        if ($nums[$i] -ne ($i + 1)) {
            $warns.Add("场次 $($g.Name)：镜号不连续（第 $($i + 1) 个是 $($nums[$i])）")
            break
        }
    }
}

$segNums = @($segmentRows.Keys | ForEach-Object { [int](($_ -replace '\D', '')) } | Sort-Object)
for ($i = 0; $i -lt $segNums.Count; $i++) {
    if ($segNums[$i] -ne ($i + 1)) {
        $warns.Add("段号不连续（第 $($i + 1) 个是 D$($segNums[$i])）")
        break
    }
}

if ($TargetSeconds -gt 0) {
    $diff = [Math]::Round($totalDuration - $TargetSeconds, 1)
    if ([Math]::Abs($diff) -gt $ToleranceSeconds) {
        $errors.Add("整集时长 ${totalDuration}s，与目标 ${TargetSeconds}s 相差 ${diff}s（容差 ±${ToleranceSeconds}s）")
    }
}

$firstThree = @($rows | Select-Object -First 3)
if (-not ($firstThree | Where-Object { (([string]$_.'标记') -replace '🔴','').Trim() -eq '钩子' })) {
    $warns.Add("前 3 镜没有'钩子'标记，冷开场可能不够强")
}
$lastThree = @($rows | Select-Object -Last 3)
if (-not ($lastThree | Where-Object { (([string]$_.'标记') -replace '🔴','').Trim() -eq '结尾悬念' })) {
    $warns.Add("最后 3 镜没有'结尾悬念'标记，集末卡点可能缺失")
}
if (-not $flagCount.ContainsKey('反转') -and -not $flagCount.ContainsKey('情绪最高点')) {
    $warns.Add("全集没有'反转'或'情绪最高点'标记")
}

Write-Output ("场次    镜头数  时长合计")
foreach ($scene in ($sceneDuration.Keys | Sort-Object)) {
    $count = @($rows | Where-Object { [string]$_.'场次' -eq $scene }).Count
    Write-Output ("{0,-8}{1,-8}{2}" -f $scene, $count, $sceneDuration[$scene])
}

Write-Output ("段号    镜数    时长    最低可生成性")
foreach ($seg in ($segmentRows.Keys | Sort-Object)) {
    $items = $segmentRows[$seg]
    $sum = 0.0
    $minGen = 100
    foreach ($it in $items) {
        $d = 0.0
        $v = ([string]$it.'时长(秒)') -replace '[^\d\.]', ''
        if ([double]::TryParse($v, [ref]$d)) { $sum += $d }
        $g = 100
        $gv = ([string]$it.'可生成性') -replace '[^\d]', ''
        if ([int]::TryParse($gv, [ref]$g) -and $g -lt $minGen) { $minGen = $g }
    }
    Write-Output ("{0,-8}{1,-8}{2,-8}{3}" -f $seg, $items.Count, $sum, $minGen)
}

Write-Output ""
Write-Output ("总镜头：$($rows.Count)    总段数：$($segmentRows.Count)    总时长：${totalDuration}s")
Write-Output ("ERROR：$($errors.Count)    WARN：$($warns.Count)")

if ($errors.Count -gt 0) {
    Write-Output ""
    Write-Output "--- 必须修复 ---"
    $errors | Select-Object -First 80 | ForEach-Object { Write-Output "ERROR  $_" }
}
if ($warns.Count -gt 0) {
    Write-Output ""
    Write-Output "--- 建议复核（前 50 条）---"
    $warns | Select-Object -First 50 | ForEach-Object { Write-Output "WARN   $_" }
}

if ($errors.Count -gt 0) { exit 1 } else { exit 0 }
