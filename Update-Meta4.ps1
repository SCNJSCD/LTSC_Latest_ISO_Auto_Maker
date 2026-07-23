# Update-Meta4.ps1
# 通过 MS 更新历史页面（主要）以及 KB 替代链和版本名称交叉验证生成 .meta4 文件。
# 修改为每个系统版本（14393、17763、19041、26100）输出单个 XML，其中同时包含 x64 和 x86 更新。
# 文件名统一格式：对于双架构版本 KBxxxxx-x64.cab / KBxxxxx-x86.msu；对于仅 x64 版本（26100）KBxxxxx.msu

[CmdletBinding()]
param([string[]]$Build = @(), [string[]]$Arch = @(), [string]$OutputDir = "", [switch]$TestMode)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutputDir) { $OutputDir = Join-Path $ScriptRoot "XML" }
if (-not (Test-Path $OutputDir)) { New-Item $OutputDir -ItemType Directory -Force | Out-Null }

$CFG = @{
    "14393" = @{OP="windows10.0";L="LTSB 2016";        S1="Cumulative Update for Windows 10 Version 1607";          S3=".NET Framework 4.8 Windows 10 1607"}
    "17763" = @{OP="windows10.0";L="LTSC 2019";        S1="Cumulative Update for Windows 10 Version 1809";          S3=".NET Framework 4.8 Windows 10 1809"}
    "19041" = @{OP="windows10.0";L="22H2 / LTSC 2021"; S1="Cumulative Update for Windows 10 Version 22H2";         S3=".NET Framework 4.8.1 Windows 10 22H2";S4=".NET Framework 4.8 Windows 10 22H2"}
    "26100" = @{OP="windows11.0";L="24H2";             S1="Cumulative Update for Windows 11 Version 24H2";         S3=".NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2"}
}
$ARCH_LABEL = @{x64="for x64-based Systems"; x86="for x86-based Systems"}
$ONLY_X64_BUILDS = @("26100")  # 仅支持 x64 的系统版本，文件名不包含架构后缀

# 辅助函数：从 URL 或文件名推断架构
function Get-ArchFromUrl {
    param([string]$Url, [string]$Fallback = "")
    if ($Url -match '-(x64|x86)(?:\.|_)') { return $matches[1].ToLower() }
    if ($Url -match '/x64/') { return "x64" }
    if ($Url -match '/x86/') { return "x86" }
    return $Fallback
}

function Convert-ToStandardFileName {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$FileObj,
        [string]$ArchHint = "",
        [string]$BuildNum = ""
    )
    $url = $FileObj.Url
    $arch = $FileObj.Language
    if (-not $arch -and $ArchHint) { $arch = $ArchHint }
    if (-not $arch) { $arch = Get-ArchFromUrl -Url $url }
    if (-not $arch) { $arch = "unknown" }
    
    $kb = ""
    if ($url -match '(?i)kb(\d+)') { $kb = "KB$($matches[1])" }
    if (-not $kb) {
        Write-Warning "无法从 URL 提取 KB 编号: $url"
        return $FileObj
    }
    $ext = ""
    if ($url -match '\.(msu|cab)$') { $ext = $matches[1].ToLower() }
    if (-not $ext) {
        Write-Warning "无法从 URL 提取扩展名: $url"
        return $FileObj
    }
    if ($BuildNum -in $ONLY_X64_BUILDS -and $arch -eq "x64") {
        $newName = "$kb.$ext"
    } else {
        $newName = "$kb-$arch.$ext"
    }
    $FileObj.FileName = $newName
    # 同时确保 Language 属性准确
    if ($FileObj.Language -ne $arch) { $FileObj.Language = $arch }
    return $FileObj
}

function Search-Catalog { param($Q)
    try { $r = Invoke-WebRequest ("https://www.catalog.update.microsoft.com/v7/site/Search.aspx?q=" + [uri]::EscapeDataString($Q)) -UseBasicParsing -TimeoutSec 30
    } catch { return @() }
    $h = $r.Content; $ret = @(); $re = [regex]"id='([a-f0-9\-]{36})_link'"
    foreach ($m in $re.Matches($h)) {
        $g = $m.Groups[1].Value; $e = $h.IndexOf("</a>", $m.Index + $m.Length)
        if ($e -le 0) { continue }
        $r2 = $h.Substring($m.Index + $m.Length, $e - $m.Index - $m.Length)
        $gt = $r2.IndexOf('>'); if ($gt -ge 0) { $r2 = $r2.Substring($gt + 1) }
        $t = ($r2 -replace '<[^>]+>', '').Trim()
        if ($t) { $ret += [PSCustomObject]@{Guid = $g; Title = $t} }
    }
    return $ret
}

function Get-Links { param($Guid)
    try { $r = Invoke-WebRequest "https://www.catalog.update.microsoft.com/DownloadDialog.aspx" -Method Post -Body @{UpdateIDs = "[{size:0,UpdateID:'$Guid',UpdateIDInfo:'$Guid'}]"} -ContentType "application/x-www-form-urlencoded" -UseBasicParsing -TimeoutSec 30
    } catch { return @() }
    $c = $r.Content -replace "www.download.windowsupdate", "download.windowsupdate"
    $out = @(); $re = [regex]"downloadInformation\[\d+\]\.files\[\d+\]\.url\s*=\s*'([^']*)'"
    foreach ($m in $re.Matches($c)) {
        $url = $m.Groups[1].Value; $fn = $url.Split('/')[-1]
        $sha1 = ""; if ($fn -match '_([a-f0-9]{40})\.(msu|cab)$') { $sha1 = $matches[1] }
        $kb = 0; if ($url -match 'kb(\d+)') { $kb = [int]$matches[1] }
        $out += [PSCustomObject]@{FileName = $fn; Url = $url; Sha1 = $sha1; KB = $kb}
    }
    return ($out | Sort-Object Url -Unique)
}

$chainCache = @{}
function Follow-Chain { param($OldKb, $ArchPat, $OsPref)
    $key = "$OldKb|$ArchPat"; if ($chainCache.ContainsKey($key)) { return $chainCache[$key] }
    $r = Search-Catalog "$OldKb"
    $first = $r | Where-Object { $_.Title -match $ArchPat } | Select-Object -First 1
    if (-not $first) { $chainCache[$key] = $null; return $null }
    try { $sv = Invoke-WebRequest ("https://www.catalog.update.microsoft.com/v7/site/ScopedViewInline.aspx?updateid=" + $first.Guid) -UseBasicParsing -TimeoutSec 15
    } catch { $chainCache[$key] = $null; return $null }
    $html = $sv.Content
    $match = [regex]::Match($html, '(?s)<div id="supersededbyInfo">(.*?)<span')
    if (-not $match.Success) { $ll = Get-Links $first.Guid; $chainCache[$key] = $ll; return $ll }
    $links = [regex]::Matches($match.Groups[1].Value, "<a[^>]*href='([^']*)'[^>]*>([^<]+)</a>")
    if ($links.Count -eq 0) { $ll = Get-Links $first.Guid; $chainCache[$key] = $ll; return $ll }
    $sorted = $links | Sort-Object { $_.Groups[2].Value } -Descending
    $guid = if ($sorted[0].Groups[1].Value -match 'updateid=([a-f0-9\-]{36})') { $matches[1] }
    if (-not $guid) { $chainCache[$key] = $null; return $null }
    $result = Get-Links $guid
    $chainCache[$key] = $result; return $result
}

function Bootstrap-Search { param($Term, $ArchPat, $OsPref, $Kind)
    $r = Search-Catalog $Term
    if ($Kind -eq "LCU") {
        $best = $r | Where-Object { $_.Title -match $ArchPat -and $_.Title -match 'Cumulative Update' -and $_.Title -notmatch '\.NET' } | Sort-Object Title -Descending | Select-Object -First 1
    } else {
        $candidates = $r | Where-Object { $_.Title -match $ArchPat -and $_.Title -match '\.NET' }
        $best = $candidates | Where-Object { $_.Title -notmatch '4\.7\.2' }
        if ($Term -notmatch '4\.8\.1') { $best = $best | Where-Object { $_.Title -notmatch '4\.8\.1' } }
        $best = $best | Sort-Object Title -Descending | Select-Object -First 1
        if (-not $best) { $best = $candidates | Sort-Object Title -Descending | Select-Object -First 1 }
    }
    if (-not $best -and $Kind -ne "LCU") {
        $candidates = $r | Where-Object { $_.Title -match '\.NET' -and $_.Title -notmatch 'for (x64|arm64)' }
        $best = $candidates | Where-Object { $_.Title -notmatch '4\.7\.2' }
        if ($Term -notmatch '4\.8\.1') { $best = $best | Where-Object { $_.Title -notmatch '4\.8\.1' } }
        $best = $best | Sort-Object Title -Descending | Select-Object -First 1
        if (-not $best) { $best = $candidates | Sort-Object Title -Descending | Select-Object -First 1 }
    }
    if (-not $best) { return $null }
    $links = Get-Links $best.Guid
    $ndpCount = ($links | Where-Object { $_.FileName -match 'ndp.*\.msu$' }).Count
    if ($ndpCount -eq 0 -and $Kind -ne 'LCU') {
        $altCandidates = $candidates | Where-Object { $_.Guid -ne $best.Guid } | Sort-Object Title -Descending
        foreach ($alt in $altCandidates) {
            $altLinks = Get-Links $alt.Guid
            if (($altLinks | Where-Object { $_.FileName -match 'ndp.*\.msu$' }).Count -gt 0) { $links = $altLinks; $best = $alt; break }
        }
    }
    $m = $links | Where-Object { $_.FileName -match [regex]::Escape($OsPref) }
    if (-not $m) { $m = $links }
    if ($Kind -eq "LCU") { return ($m | Where-Object { $_.FileName -match '\.msu$' -and $_ -notmatch 'ndp' } | Sort-Object KB -Descending | Select-Object -First 1) }
    return ($m | Where-Object { $_.FileName -match 'ndp.*\.msu$' } | Select-Object -First 1)
}

function Pick-File($Links, $Kind, $OsPref) {
    $m = $Links | Where-Object { $_.FileName -match [regex]::Escape($OsPref) }
    if (-not $m) { $m = $Links }
    if ($Kind -eq "LCU") { return ($m | Where-Object { $_.FileName -match '\.msu$' -and $_ -notmatch 'ndp' } | Sort-Object KB -Descending | Select-Object -First 1) }
    if ($Kind -eq "SSU") { return ($m | Where-Object { $_.FileName -match '\.msu$' -and $_ -notmatch 'ndp' } | Sort-Object KB | Select-Object -First 1) }
    if ($Kind -eq "NET") {
        $r = $m | Where-Object { $_.FileName -match 'ndp.*\.msu$' }
        $filtered = $r | Where-Object { $_.FileName -match "^$OsPref" }
        if ($filtered) { $r = $filtered }
        return $r | Select-Object -First 1
    }
    return $m | Select-Object -First 1
}

function New-Meta4($F) {
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('<metalink xmlns="urn:ietf:params:xml:ns:metalink"')
    $null = $sb.AppendLine("`txmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xsi:noNamespaceSchemaLocation=""metalink4.xsd"">")
    foreach ($f in $F) {
        $null = $sb.AppendLine("`t<file name=""$($f.FileName)"">")
        if ($f.Language -and $f.Language -ne "") {
            $null = $sb.AppendLine("`t`t<language>$($f.Language)</language>")
        }
        $null = $sb.AppendLine("`t`t<hash type=""sha-1"">$($f.Sha1)</hash>")
        $null = $sb.AppendLine("`t`t<url>$($f.Url)</url>")
        $null = $sb.AppendLine("`t</file>")
    }
    $null = $sb.AppendLine('</metalink>')
    return $sb.ToString()
}

# 从现有的 meta4 文件中提取所有 .cab 文件，并附带 Language 信息
function Get-Cabs($P) {
    if (-not (Test-Path $P)) { return @() }
    try { $x = [xml](Get-Content $P -Raw)
        return $x.metalink.file | Where-Object { $_.name -match '\.cab$' } | ForEach-Object {
            $ckb = 0; if ($_.name -match 'kb(\d+)') { $ckb = [int]$matches[1] }
            $lang = if ($_.language) { $_.language } else { "" }
            # 如果 language 为空，从文件名推断
            if (-not $lang) {
                if ($_.name -match '-x64\.cab') { $lang = "x64" }
                elseif ($_.name -match '-x86\.cab') { $lang = "x86" }
            }
            [PSCustomObject]@{FileName = $_.name; Url = $_.url; Sha1 = $_.hash.'#text'; KB = $ckb; Language = $lang}
        }
    } catch { return @() }
}

function Get-KB($F) { if ($F.FileName -match 'kb(\d+)') { $matches[1] } else { "" } }

# 标准化后的 .NET 文件名不再包含 ndp，因此同时检查原始下载 URL。
function Test-IsNetMsu($File) {
    if (-not $File) { return $false }

    $name = [string]$File.FileName
    if (-not $name) { $name = [string]$File.name }

    $url = [string]$File.Url
    if (-not $url) { $url = [string]$File.url }

    return (($name -match '(?i)ndp.*\.msu$') -or ($url -match '(?i)ndp.*\.msu(?:$|\?)'))
}

function Get-OldKBFromFile($Path, $Kind, $ArchPat, $Arch) {
    if (-not (Test-Path $Path)) { return $null }
    try { $x = [xml](Get-Content $Path -Raw)
        $all = $x.metalink.file
        if ($Kind -eq "LCU") {
            $cands = $all | Where-Object { $_.name -match '\.msu$' -and -not (Test-IsNetMsu $_) -and $_.name -match $Arch } | Sort-Object { if ($_.name -match 'kb(\d+)') { [int]$matches[1] } else { 0 } } -Descending
            foreach ($c in $cands) {
                if ($c.name -match 'kb(\d+)') {
                    $ckb = [int]$matches[1]
                    try {
                        $r = Search-Catalog "kb$ckb"
                        $t = ($r | Where-Object { $_.Title -match $ArchPat } | Select-Object -First 1).Title
                        if ($t -match 'Cumulative Update' -and $t -notmatch '\.NET') {
                            return $ckb
                        }
                    } catch { continue }
                }
            }
            $first = $cands | Select-Object -First 1
            if ($first -and $first.name -match 'kb(\d+)') { return [int]$matches[1] }
        }
        if ($Kind -eq "NET") {
            $first = $all | Where-Object { (Test-IsNetMsu $_) -and $_.name -match $Arch } | Select-Object -First 1
            if ($first -and $first.name -match 'kb(\d+)') { return [int]$matches[1] }
        }
    } catch { }
    return $null
}

function Cross-Validate($ChainFile, $BootFile, $Label) {
    if (-not $ChainFile -and -not $BootFile) { return $null, "SKIP" }
    if ($ChainFile -and $BootFile) {
        if ($ChainFile.KB -eq $BootFile.KB) { return $ChainFile, "verified" }
        return $BootFile, "bootstrapped (chain mismatch)"
    }
    if ($ChainFile) { return $ChainFile, "chain" }
    return $BootFile, "bootstrapped"
}

$historyPageCache = @{}
function Get-HistoryBuild($TopicId, $BuildPat) {
    $cacheKey = "histPage_$TopicId"
    if (-not $historyPageCache.ContainsKey($cacheKey)) {
        $url = "https://support.microsoft.com/en-us/topic/$TopicId"
        $r = $null
        $retry = 0; while ($retry -lt 3) {
            try { $r = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 15; break }
            catch { $retry++; if ($retry -ge 3) { return $null }; Start-Sleep -Milliseconds 2000 }
        }
        $historyPageCache[$cacheKey] = $r.Content
    }
    $h = $historyPageCache[$cacheKey]
    $re = [regex]'<a class="supLeftNavLink"[^>]*>([^<]+)</a>'
    $entries = @()
    foreach ($m in $re.Matches($h)) {
        $text = $m.Groups[1].Value -replace '&#x2014;', ''
        if ($text -match "program") { continue }
        $kbMatch = [regex]::Match($text, 'KB(\d+)')
        $reBuild = [regex]"((?:$BuildPat)\.\d+)"
        $buildMatch = $reBuild.Match($text)
        if ($kbMatch.Success -and $buildMatch.Success) {
            $entries += [PSCustomObject]@{ KB=[int]$kbMatch.Groups[1].Value; Build=$buildMatch.Groups[1].Value }
        }
    }
    if ($entries.Count -eq 0) { return $null }
    return $entries | Sort-Object { $_.Build.Split('.')[-1] -as [int] } -Descending | Select-Object -First 1
}

function Get-HistoryBuildPat($bn) {
    $pat = $bn
    if ($bn -eq "19041") { $pat = "1904\d" }
    return $pat
}

function Get-OldMsus($Path, $ArchFilter = $null) {
    if (-not (Test-Path $Path)) { return @() }
    try {
        $x = [xml](Get-Content $Path -Raw)
        $msus = $x.metalink.file | Where-Object { $_.name -match '\.msu$' -and -not (Test-IsNetMsu $_) }
        if ($ArchFilter) { $msus = $msus | Where-Object { $_.name -match $ArchFilter } }
        return @($msus | ForEach-Object {
            $kb = 0; if ($_.name -match 'kb(\d+)') { $kb = [int]$matches[1] }
            $lang = if ($_.language) { $_.language } else { "" }
            [PSCustomObject]@{FileName = $_.name; Url = $_.url; Sha1 = $_.hash.'#text'; KB = $kb; Language = $lang}
        })
    } catch { return @() }
}

function Get-ExistingFiles($Path) {
    if (-not (Test-Path $Path)) { return @() }
    try {
        $x = [xml](Get-Content $Path -Raw)
        return $x.metalink.file | ForEach-Object {
            $kb = 0; if ($_.name -match 'kb(\d+)') { $kb = [int]$matches[1] }
            $sha = if ($_.hash) { $_.hash.'#text' } else { "" }
            $lang = if ($_.language) { $_.language } else { "" }
            [PSCustomObject]@{FileName = $_.name; Url = $_.url; Sha1 = $sha; KB = $kb; Language = $lang}
        }
    } catch { return @() }
}

function Add-CheckpointCU($OldMeta4, $CurrentFiles, $BuildNum, $ArchFilter) {
    if ($BuildNum -ne "26100") { return $CurrentFiles }
    $oldMsus = Get-OldMsus $OldMeta4 $ArchFilter
    $checkpointCUs = $oldMsus | Where-Object { $_.KB -eq 5043080 }
    foreach ($cp in $checkpointCUs) {
        if ($cp.Url -notin $CurrentFiles.Url) {
            # 确保架构正确
            $arch = $cp.Language
            if (-not $arch) { $arch = Get-ArchFromUrl -Url $cp.Url -Fallback $ArchFilter }
            $cpObj = [PSCustomObject]@{
                FileName = $cp.FileName
                Url = $cp.Url
                Sha1 = $cp.Sha1
                KB = $cp.KB
                Language = $arch
            }
            $cpObj = Convert-ToStandardFileName -FileObj $cpObj -ArchHint $arch -BuildNum $BuildNum
            $CurrentFiles += $cpObj
        }
        Write-Host "  [CHECKPOINT] KB$($cp.KB)" -ForegroundColor DarkGray
    }
    return @($CurrentFiles | Sort-Object Url -Unique)
}

$cabTypeCache = @{}
function Get-CabType($File, $ArchPat) {
    $kb = $File.KB
    if (-not $kb) { return 3 }
    if ($cabTypeCache.ContainsKey($kb)) { return $cabTypeCache[$kb] }
    try {
        $sr = Search-Catalog "kb$kb"
        $sb = $sr | Where-Object { $_.Title -match $ArchPat } | Select-Object -First 1
        if ($sb) {
            $title = $sb.Title
            if ($title -match "Setup Dynamic Update") { $cabTypeCache[$kb] = 1; return 1 }
            if ($title -match "Safe OS") { $cabTypeCache[$kb] = 2; return 2 }
            $ssv = Invoke-WebRequest "https://www.catalog.update.microsoft.com/v7/site/ScopedViewInline.aspx?updateid=$($sb.Guid)" -UseBasicParsing -TimeoutSec 10
            $ssh = $ssv.Content
            if ($ssh -match "SetupUpdate:|setup binaries") { $cabTypeCache[$kb] = 1; return 1 }
            if ($ssh -match "Safe OS") { $cabTypeCache[$kb] = 2; return 2 }
            $cabTypeCache[$kb] = 3; return 3
        }
    } catch { }
    $cabTypeCache[$kb] = 3; return 3
}

$AllowedBuilds = @("14393","17763","19041","26100")
if ($Build.Count -eq 1 -and $Build[0] -match ',') { $Build = $Build[0] -split ',' | ForEach-Object { $_.Trim() } }
$Build = $Build | Where-Object { $_ -in $AllowedBuilds }
if ($Build.Count -eq 0) { $Build = $AllowedBuilds }

if ($Arch.Count -eq 1 -and $Arch[0] -match ',') { $Arch = $Arch[0] -split ',' | ForEach-Object { $_.Trim() } }
if ($Arch.Count -eq 0) { $Arch = @("x64", "x86") }
$Arch = $Arch | Where-Object { $_ -in @("x64","x86") }

$gen = 0; $skip = 0; $BUILD_VERSIONS = @{}

foreach ($bn in $Build) {
    $c = $CFG[$bn]; if (-not $c) { continue }
    $outputFile = Join-Path $OutputDir "${bn}.xml"
    $allFiles = @()

    Write-Host "--- [$bn] $($c.L) ---" -ForegroundColor Yellow

    foreach ($ar in $Arch) {
        $al = $ARCH_LABEL[$ar]
        $ap = "for $ar" + "[^a-z]"
        if (-not $al) { continue }

        if ($bn -in $ONLY_X64_BUILDS -and $ar -eq "x86") {
            Write-Host "  [$ar] 跳过（$bn 仅支持 x64）" -ForegroundColor DarkGray
            continue
        }

        Write-Host "  [$ar] processing..." -ForegroundColor Cyan

        $oldMeta4 = $outputFile
        if (-not (Test-Path $oldMeta4)) {
            $oldMeta4 = Join-Path $OutputDir "script_${bn}_${ar}.meta4"
        }

        $newFiles = @()

        # 1. LCU
        Write-Host "    LCU..." -NoNewline
        try {
            $chain = $null; $boot = $null
            $okb = Get-OldKBFromFile $oldMeta4 "LCU" $ap $ar
            if ($okb) { $cl = Follow-Chain -OldKb $okb -ArchPat $ap -OsPref $c.OP; $chain = Pick-File $cl "LCU" $c.OP }
            $boot = Bootstrap-Search -Term $c.S1 -ArchPat $ap -OsPref $c.OP -Kind "LCU"
            $f, $tag = Cross-Validate $chain $boot "LCU"
            if ($f) { 
                $f | Add-Member -NotePropertyName Language -NotePropertyValue $ar -Force
                $f = Convert-ToStandardFileName -FileObj $f -ArchHint $ar -BuildNum $bn
                $newFiles += $f
                Write-Host " $($f.FileName) ($tag)" -ForegroundColor $(if($tag-match"^history"){"Green"}elseif($tag-eq"verified"){"Green"}elseif($tag-eq"chain"){"Cyan"}else{"Yellow"})
            } else { Write-Host " SKIP"; $skip++; continue }
        } catch { Write-Host " ERROR: $_"; $skip++; continue }

        # 2. SSU (仅 14393)
        if ($bn -eq "14393") {
            Start-Sleep -Milliseconds 600
            $ssuOldKb = $null; $ssuNewFile = $null
            if (Test-Path $oldMeta4) {
                $ssuR = Search-Catalog "Servicing Stack Update for Windows 10 Version 1607 for $ar-based Systems"
                $ssuFiltered = $ssuR | Where-Object { $_.Title -match "Servicing Stack" -and $_.Title -match "for $ar[^a-z]" -and $_.Title -match "Version 1607" }
                $ssuOldMsus = Get-OldMsus $oldMeta4 $ar
                $ssuOldLcuKb = Get-OldKBFromFile $oldMeta4 "LCU" $ap $ar
                foreach ($ssuOldResult in $ssuFiltered) {
                    if ($ssuOldResult.Title -match 'KB(\d+)') {
                        $ssuOldKbCandidate = [int]$matches[1]
                        if ($ssuOldKbCandidate -ne $ssuOldLcuKb -and ($ssuOldMsus.KB -contains $ssuOldKbCandidate)) {
                            $ssuOldKb = $ssuOldKbCandidate; break
                        }
                    }
                }
            }
            if ($ssuOldKb) {
                $ssuChain = Follow-Chain -OldKb $ssuOldKb -ArchPat $ap -OsPref $c.OP
                $ssuNewFile = Pick-File $ssuChain "SSU" $c.OP
            }
            if ($ssuNewFile) {
                $ssuNewFile | Add-Member -NotePropertyName Language -NotePropertyValue $ar -Force
                $ssuNewFile = Convert-ToStandardFileName -FileObj $ssuNewFile -ArchHint $ar -BuildNum $bn
                $newFiles += $ssuNewFile
                Write-Host "    [SSU] $ssuOldKb -> $($ssuNewFile.KB)" -ForegroundColor Green
            } else {
                Write-Host "    SSU: none" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "    SSU: bundled" -ForegroundColor DarkGray
        }

        Start-Sleep -Milliseconds 600

        # 3. .NET
        Write-Host "    .NET..." -NoNewline
        try {
            $chain = $null; $boot = $null
            $okb = Get-OldKBFromFile $oldMeta4 "NET" $ap $ar
            if ($okb) { $cl = Follow-Chain -OldKb $okb -ArchPat $ap -OsPref $c.OP; $chain = Pick-File $cl "NET" $c.OP }
            $boot = Bootstrap-Search -Term $c.S3 -ArchPat $ap -OsPref $c.OP -Kind "NET"
            if (-not $boot -and $c.S4) { $boot = Bootstrap-Search -Term $c.S4 -ArchPat $ap -OsPref $c.OP -Kind "NET" }
            $f, $tag = Cross-Validate $chain $boot "NET"
            if ($f -and $f.FileName -notmatch "^$($c.OP)") { $f = $null; $tag = "SKIP (OS mismatch)" }
            if ($f) {
                $f | Add-Member -NotePropertyName Language -NotePropertyValue $ar -Force
                $f = Convert-ToStandardFileName -FileObj $f -ArchHint $ar -BuildNum $bn
                $newFiles += $f
                Write-Host " $($f.FileName) ($tag)" -ForegroundColor $(if($tag-eq"verified"){"Green"}elseif($tag-eq"chain"){"Cyan"}else{"Yellow"})
            } else {
                Write-Host " $tag" -ForegroundColor DarkGray
            }
        } catch { Write-Host " ERROR: $_" -ForegroundColor Red }

        # 4. 不保留旧 MSU
        # 当前 XML 只写入本次解析得到的 LCU、SSU 和 .NET 更新。
        # 旧 XML 中已被替代、无法分类或不再需要的 MSU 不得重新加入 $newFiles。
        # Windows 11 24H2 所需的检查点 CU 由 Add-CheckpointCU 单独处理。

        # 5. CAB 链
        $oldCabs = Get-Cabs $oldMeta4
        foreach ($oc in $oldCabs) {
            $oldKb = Get-KB $oc
            if ($oldKb) {
                $links = Follow-Chain -OldKb $oldKb -ArchPat $ap -OsPref $c.OP
                $cab = $links | Where-Object { $_.FileName -match '\.cab$' } | Select-Object -First 1
                if ($cab -and $cab.FileName -ne $oc.FileName -and ($cab.Url -notin $newFiles.Url)) {
                    # 从 URL 推断架构
                    $cabArch = Get-ArchFromUrl -Url $cab.Url -Fallback $ar
                    $cab | Add-Member -NotePropertyName Language -NotePropertyValue $cabArch -Force
                    $cab = Convert-ToStandardFileName -FileObj $cab -ArchHint $cabArch -BuildNum $bn
                    $cabType = switch (Get-CabType $cab $ap) { 1 { "CAB_SETUP" } 2 { "CAB_SAFEOS" } default { "CAB" } }
                    $newFiles += $cab; Write-Host "    [$cabType] $oldKb -> $($cab.FileName)" -ForegroundColor Green
                } elseif ($oc.Url -notin ($newFiles | ForEach-Object { $_.Url })) {
                    # 保留旧 CAB，确保 Language 正确
                    $ocArch = $oc.Language
                    if (-not $ocArch) { $ocArch = Get-ArchFromUrl -Url $oc.Url -Fallback $ar }
                    $ocCopy = [PSCustomObject]@{FileName=$oc.FileName; Url=$oc.url; Sha1=$oc.Sha1; KB=$oc.KB; Language=$ocArch}
                    $ocCopy = Convert-ToStandardFileName -FileObj $ocCopy -ArchHint $ocArch -BuildNum $bn
                    $cabType = switch (Get-CabType $ocCopy $ap) { 1 { "CAB_SETUP" } 2 { "CAB_SAFEOS" } default { "CAB" } }
                    $newFiles += $ocCopy; Write-Host "    [$cabType] $oldKb (unchanged)" -ForegroundColor DarkGray
                }
            } elseif ($oc.Url -notin ($newFiles | ForEach-Object { $_.Url })) {
                $ocArch = $oc.Language
                if (-not $ocArch) { $ocArch = Get-ArchFromUrl -Url $oc.Url -Fallback $ar }
                $ocCopy = [PSCustomObject]@{FileName=$oc.FileName; Url=$oc.url; Sha1=$oc.Sha1; KB=$oc.KB; Language=$ocArch}
                $ocCopy = Convert-ToStandardFileName -FileObj $ocCopy -ArchHint $ocArch -BuildNum $bn
                $newFiles += $ocCopy
            }
            Start-Sleep -Milliseconds 400
        }

        $newFiles = Add-CheckpointCU -OldMeta4 $oldMeta4 -CurrentFiles $newFiles -BuildNum $bn -ArchFilter $ar
        $allFiles += $newFiles
    }

    $allFiles = $allFiles | Sort-Object Url -Unique

    $maxLCUKb = ($allFiles | Where-Object { $_.FileName -match '\.msu$' -and -not (Test-IsNetMsu $_) } | Measure-Object -Property KB -Maximum).Maximum

    $sortedAll = $allFiles | Sort-Object @{Expression={
        $n = $_.FileName
        $isCab = $n -match '\.cab$'
        $isNdp = Test-IsNetMsu $_
        $isMsu = ($n -match '\.msu$') -and (-not $isNdp)
        $isCheckpoint = ($_.KB -eq 5043080)

        if ($isCab) {
            $archPat = if ($_.Language -eq 'x64') { 'for x64[^a-z]' } else { 'for x86[^a-z]' }
            $cabType = Get-CabType $_ $archPat
            return 50000000 + $cabType
        }
        if ($isNdp) { return 40000000 }
        if ($isCheckpoint) { return 10000000 }
        if ($isMsu) {
            if ($_.KB -eq $maxLCUKb) { return 20000000 }
            return 30000000
        }
        return 60000000
    }}
    $sortedAll = $sortedAll | Sort-Object @{Expression={
        if ($_.Language -eq 'x64') { return 1 }
        if ($_.Language -eq 'x86') { return 2 }
        return 3
    }}, @{Expression={$_.KB}} -Descending

    if ($TestMode) { 
        Write-Host "  [TEST] $($sortedAll.Count) entries for $bn" -ForegroundColor DarkGray
        $gen++
        continue
    }

    $xml = New-Meta4 $sortedAll
    $xml | Out-File $outputFile -Encoding utf8 -NoNewline
    Write-Host "  [OK] $($sortedAll.Count) files -> $($bn).xml" -ForegroundColor Green
    $gen++
}

Write-Host "=== Done: $gen generated, $skip skipped ===" -ForegroundColor Cyan
