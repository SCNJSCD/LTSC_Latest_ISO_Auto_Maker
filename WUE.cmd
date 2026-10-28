@echo off
setlocal DisableDelayedExpansion
rem WUE - Windows Update Extractor. Single-file CMD/Windows PowerShell hybrid.
rem Extraction paths adapted from W10UI v10.65: cab1/msu1, cab2, psfx2,
rem inrenssu/uupssu, get_dll and cabpsf. No servicing or installation actions.
set "WUE_SELF=%~f0"
set "WUE_INPUT="
set "WUE_TARGET="
set "WUE_NOARCH=0"
set "WUE_SHOWDETAIL=0"
set "WUE_EXPORTINFO=0"
:args
if "%~1"=="" goto run
if /i "%~1"=="--help" goto help
if /i "%~1"=="/?" goto help
if /i "%~1"=="--no-arch" (
  set "WUE_NOARCH=1"
  shift
  goto args
)
if /i "%~1"=="--show-detail" (
  set "WUE_SHOWDETAIL=1"
  shift
  goto args
)
if /i "%~1"=="--export-info" (
  set "WUE_EXPORTINFO=1"
  shift
  goto args
)
if not defined WUE_INPUT (
  set "WUE_INPUT=%~1"
  shift
  goto args
)
if not defined WUE_TARGET (
  set "WUE_TARGET=%~1"
  shift
  goto args
)
echo ERROR: Too many arguments.
exit /b 2
:help
echo Usage: WUE.cmd update_file_path [target_path] [--no-arch] [--show-detail] [--export-info]
echo.
echo CAB/MSU/WIM contents are detected by signature, not extension.
echo WIM requires wimlib-imagex.exe: script directory first, then current directory/PATH.
echo target_path is the output root; default: the input file's directory.
echo Each update gets a KB1234567-x64 folder, or KB1234567 with --no-arch.
echo Existing output folders are never overwritten. Quote paths with spaces.
echo By default only final Output: paths are shown. --show-detail shows progress.
echo --export-info writes _NET.txt, _SSU.txt, _LCU.txt and _SDU.txt in the current directory.
echo NET/SSU/LCU contain KB numbers; SDU contains the CAB name without -x64/-x86.
echo Only recognised types are written; each file keeps the last matching update.
exit /b 0
:run
if not defined WUE_INPUT (
  call :help
  exit /b 2
)
rem Environment variables keep filenames out of executable PowerShell text.
rem Use Windows PowerShell/.NET Framework, including from a 32-bit CMD host.
set "WUE_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "WUE_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%WUE_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:WUE_SELF); $p=$s.LastIndexOf('# WUE_POWERSHELL_BEGIN'); & ([scriptblock]::Create($s.Substring($p)))"
exit /b %errorlevel%
# WUE_POWERSHELL_BEGIN
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Write-Detail([string]$Message) {
    if ($env:WUE_SHOWDETAIL -eq '1') { Write-Host $Message }
}

function Read-Xml([string]$Path) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($Path, $settings)
    try { $doc = New-Object System.Xml.XmlDocument; $doc.XmlResolver = $null; $doc.Load($reader); return ,$doc }
    finally { $reader.Dispose() }
}

function Get-Format([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $bytes = New-Object byte[] 8
        $n = $stream.Read($bytes, 0, 8)
        if ($n -ge 4 -and [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq 'MSCF') { return 'CAB' }
        if ($n -eq 8 -and [BitConverter]::ToString($bytes) -eq '4D-53-57-49-4D-00-00-00') { return 'WIM' }
        return 'UNKNOWN'
    } finally { $stream.Dispose() }
}

function Invoke-Tool([string]$Exe, [string[]]$Arguments, [switch]$ShowOutput) {
    # Windows PowerShell wraps native stderr as ErrorRecord objects. Capture
    # warnings too, and decide success from the tool's exit code.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $Exe @Arguments 2>&1)
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = -1 }
    } finally { $ErrorActionPreference = $savedPreference }
    if ($code -ne 0) {
        $log = Join-Path $script:Work ('tool-error-' + [guid]::NewGuid().ToString('N') + '.log')
        [IO.File]::WriteAllLines($log, [string[]]$lines)
        $detail = @($lines | Where-Object { [string]$_ -notmatch '^(?i)Adding |Progress:' -and [string]$_ -match '(?i)error|incomplete|could not|cannot|failed|0x[0-9a-f]{8}' } | Select-Object -Last 8 | ForEach-Object { $line=[string]$_; if ($line.Length -gt 600) { $line.Substring(0,600) } else { $line } })
        throw ('{0} failed ({1}).{2}{3}{2}Full log: {4}' -f $Exe, $code, [Environment]::NewLine, ($detail -join [Environment]::NewLine), $log)
    }
    if ($ShowOutput) { foreach ($line in $lines) { Write-Detail ([string]$line) } }
}

function Get-PeMachine([string]$Path) {
    $reader = New-Object IO.BinaryReader([IO.File]::OpenRead($Path))
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { return 0 }
        $reader.BaseStream.Position = 0x3c; $pe = $reader.ReadInt32()
        if ($pe -lt 64 -or $pe -gt $reader.BaseStream.Length - 6) { return 0 }
        $reader.BaseStream.Position = $pe
        if ($reader.ReadUInt32() -ne 0x4550) { return 0 }
        return $reader.ReadUInt16()
    } finally { $reader.Dispose() }
}

function Get-LegacyExpander([string]$Directory) {
    # W10UI extract/get_dll switches DPX for targets <17763 on hosts >=22621.
    # Use the Microsoft DPX already carried by this update, in a private folder.
    if ([Environment]::OSVersion.Version.Build -lt 22621) { return $null }
    $candidates = @(Get-ChildItem -LiteralPath $Directory -Directory -Filter '*_microsoft-windows-deltapackageexpander_*')
    foreach ($component in $candidates) {
        if ($component.Name -notmatch '_10\.0\.(\d+)\.\d+_' -or [int]$Matches[1] -ge 17763) { continue }
        $dll = Join-Path $component.FullName 'dpx.dll'
        if (!(Test-Path -LiteralPath $dll -PathType Leaf)) { continue }
        $machine = Get-PeMachine $dll
        foreach ($systemDirectory in @($script:SystemBin, (Join-Path $env:SystemRoot 'SysWOW64'))) {
            $exe = Join-Path $systemDirectory 'expand.exe'
            if (!(Test-Path -LiteralPath $exe -PathType Leaf) -or (Get-PeMachine $exe) -ne $machine) { continue }
            $private = Join-Path $script:Work ('compat-' + [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($private)
            [IO.File]::Copy($dll, (Join-Path $private 'dpx.dll'))
            [IO.File]::Copy($exe, (Join-Path $private 'expand.exe'))
            return (Join-Path $private 'expand.exe')
        }
    }
    return $null
}

function Invoke-CabTool([string]$Directory, [string[]]$Arguments) {
    try { Invoke-Tool $script:Expand $Arguments }
    catch {
        $originalError = $_
        $compat = Get-LegacyExpander $Directory
        if (!$compat) { throw $originalError }
        Write-Detail 'Retrying with the update package''s legacy Microsoft dpx.dll...'
        Invoke-Tool $compat $Arguments
    }
}

function Prepare-LegacyExpander([string]$Directory, [object]$Identity, [object[]]$Parts) {
    if ([Environment]::OSVersion.Version.Build -lt 22621 -or !$Identity.PackageVersion) { return $null }
    $version = [version]$Identity.PackageVersion
    $build = $version.Major
    if ($version.Major -lt 10000) { $build = $version.Build }
    if ($build -lt 0 -or $build -ge 17763) { return $null }
    $compat = Get-LegacyExpander $Directory
    if ($compat) { return $compat }
    # Like W10UI get_dll, acquire DPX before the full payload expansion. Here
    # the update itself supplies it, rather than a mounted target Windows tree.
    $probe = Join-Path $script:Work ('dpx-probe-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($probe)
    foreach ($part in $Parts) {
        $listing = @(& $script:Expand '-d' '-f:*dpx.dll' $part.FullName 2>&1)
        # expand -d lists only the basename, even for directory members.
        if ($LASTEXITCODE -ne 0 -or ($listing -join "`n") -notmatch '(?i):\s*dpx\.dll\s*(?:\r?\n|$)') { continue }
        try { Invoke-Tool $script:Expand @('-f:*dpx.dll', $part.FullName, $probe) }
        catch { continue }
        $compat = Get-LegacyExpander $probe
        if ($compat) { return $compat }
    }
    return $null
}

function Expand-Archive([string]$Path, [string]$Destination) {
    [void][IO.Directory]::CreateDirectory($Destination)
    $format = Get-Format $Path
    Write-Detail ('Extracting [{0}]: {1}' -f $format, [IO.Path]::GetFileName($Path))
    switch ($format) {
        'CAB' { Invoke-CabTool $Destination @('-r', '-f:*', $Path, $Destination) }
        'WIM' {
            # Resolve lazily: CAB-only updates do not need wimlib. Extract index
            # 1 for both outer MSUs and nested WIMs, preserving the full tree.
            if (!$script:Wimlib) {
                $script:Wimlib = Find-Wimlib
                if (!$script:Wimlib) {
                    throw 'wimlib-imagex.exe is required for WIM archives. Place it beside WUE.cmd or in the current directory/PATH.'
                }
                Write-Detail ('Using wimlib: {0}' -f $script:Wimlib)
            }
            Invoke-Tool $script:Wimlib @('extract', $Path, '1', ('--dest-dir=' + $Destination), '--no-acls', '--no-attributes', '--check') -ShowOutput
        }
        default { throw "Unsupported or damaged archive: $Path (expected CAB or WIM signature)." }
    }
    if (@(Get-ChildItem -LiteralPath $Destination -Force).Count -eq 0) { throw "Archive produced no files: $Path" }
}

function Get-Identity([string]$Directory, [string]$Archive, [string]$InheritedArch) {
    $kb = ''; $arch = ''; $packageName = ''; $packageVersion = ''
    $updateTypes = @()
    $name = [IO.Path]::GetFileNameWithoutExtension($Archive)
    $mum = Join-Path $Directory 'update.mum'
    if (Test-Path -LiteralPath $mum -PathType Leaf) {
        $xml = Read-Xml $mum
        $package = $xml.SelectSingleNode('/*[local-name()="assembly"]/*[local-name()="package"]')
        $identity = $xml.SelectSingleNode('/*[local-name()="assembly"]/*[local-name()="assemblyIdentity"]')
        if ($package -and $package.GetAttribute('identifier') -match '(?i)\bKB\d+\b') { $kb = $Matches[0].ToUpperInvariant() }
        if ($identity) {
            $arch = $identity.GetAttribute('processorArchitecture')
            $packageName = $identity.GetAttribute('name')
            $packageVersion = $identity.GetAttribute('version')
            if (!$kb -and $identity.GetAttribute('name') -match '(?i)KB\d+') { $kb = $Matches[0].ToUpperInvariant() }
            # Preserve WUE_Old's kb_arch classification, including 14393 SSUs.
            if ($packageName -match '(?i)DotNetRollup') { $updateTypes += 'NET' }
            if ($packageName -match '(?i)ServicingStack') { $updateTypes += 'SSU' }
            if ($packageName -match '(?i)RollupFix') { $updateTypes += 'LCU' }
            if ($packageName -match '(?i)Package_for_KB' -and $packageVersion -match '14393\.' -and $updateTypes -notcontains 'SSU') { $updateTypes += 'SSU' }
        }
    }
    if (!$kb -and $name -match '(?i)KB\d+') { $kb = $Matches[0].ToUpperInvariant() }
    if (!$arch -or $arch -eq 'neutral' -or $arch -eq '*') {
        if ($name -match '(?i)(?:^|[-_])(amd64|x64|x86|arm64|arm)(?:$|[-_.])') { $arch = $Matches[1] }
        else { $arch = $InheritedArch }
    }
    $arch = $arch.ToLowerInvariant()
    if ($arch -eq 'amd64') { $arch = 'x64' }
    if ($arch -eq 'neutral' -or $arch -eq '*') { $arch = '' }
    $folder = $kb
    if (!$folder) { $folder = $name -replace '[<>:"/\\|?*\x00-\x1f]', '_' }
    if ($env:WUE_NOARCH -ne '1' -and $arch -and $folder -notmatch ('(?i)(?:^|[-_])' + [regex]::Escape($arch) + '$')) { $folder += '-' + $arch }
    # Without a KB, still honour --no-arch for the fallback archive name.
    if ($env:WUE_NOARCH -eq '1' -and !$kb) { $folder = $folder -replace '(?i)[-_](amd64|x64|x86|arm64|arm)$', '' }
    $folder = $folder.TrimEnd('.', ' ')
    if (!$folder -or $folder -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { $folder = 'Update-' + $folder }
    return [pscustomobject]@{ KB = $kb; Arch = $arch; Folder = $folder; PackageName = $packageName;
        PackageVersion = $packageVersion; IsSSU = ($packageName -match '(?i)ServicingStack'); UpdateTypes = $updateTypes }
}

function Export-UpdateInfo([object[]]$Updates, [string]$Directory) {
    # Like WUE_Old, keep the last update per type and leave unrelated files alone.
    $info = @{}
    foreach ($update in $Updates) {
        # Re-read the completed payload: CAB parts or PSF may supply update.mum.
        $identity = Get-Identity $update.Destination $update.Archive $update.Identity.Arch
        # WUE_Old's plain CAB branch identifies setup DU by root-level DLLs.
        # Manifest-based updates keep their own classification.
        if (!(Test-Path -LiteralPath (Join-Path $update.Destination 'update.mum') -PathType Leaf) -and
            (Get-Format $update.Archive) -eq 'CAB' -and
            @(Get-ChildItem -LiteralPath $update.Destination -File -Filter '*.dll').Count -gt 0) {
            $info['SDU'] = [IO.Path]::GetFileNameWithoutExtension($update.Archive) -replace '(?i)-x64|-x86', ''
        }
        if (!$identity.KB) { continue }
        foreach ($type in $identity.UpdateTypes) { $info[$type] = $identity.KB }
    }
    foreach ($type in @('NET', 'SSU', 'LCU', 'SDU')) {
        if (!$info.ContainsKey($type)) { continue }
        $path = Join-Path $Directory ('_' + $type + '.txt')
        [IO.File]::WriteAllText($path, ($info[$type] + "`r`n"))
        Write-Detail ('Exported update info: {0}' -f $path)
    }
}

function Test-UpdateArchive([IO.FileInfo]$File) {
    if ($File.Extension -notmatch '^(?i:\.cab|\.msu|\.wim)$') { return $false }
    if ($File.Name -match '(?i)(AggregatedMetadata|CompDB|DesktopDeployment|WSUSSCAN)') { return $false }
    if ((Get-Format $File.FullName) -eq 'WIM') { return $true }
    # Arbitrarily renamed embedded CABs are recognised from their members.
    $listing = @(& $script:Expand '-d' '-f:*' $File.FullName 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Cannot list embedded archive: $($File.FullName)" }
    return (($listing -join "`n") -match '(?im)(?:^|[\\\s:])(update\.mum|toc\.xml)(?:\s|$)' -or
        $File.Name -match '(?i)^(?:Windows\d.*-KB\d+|SSU-|RCU-)')
}

function Collect-Updates([string]$Archive, [string]$InheritedArch = '', [int]$Depth = 0) {
    if ($Depth -gt 12) { throw "Too many nested update containers: $Archive" }
    # W10UI detector/tmprenssu process standalone SSUs first. uupssu/inrenssu
    # then check for an existing SSU-<version>-<arch>*.cab before extraction.
    # Track those SSU identities in memory; do not hash every large archive.
    $ssuKey = ''
    $stem = [IO.Path]::GetFileNameWithoutExtension($Archive)
    if ([IO.Path]::GetExtension($Archive) -eq '.cab' -and $stem -match '(?i)^SSU-([\d.]+)-(x86|x64|amd64|arm64|arm)(?:$|[-_])') {
        $ssuKey = $Matches[1] + '|' + ($Matches[2].ToLowerInvariant() -replace '^amd64$', 'x64')
    }
    if ($ssuKey -and $script:SeenSsuNames.Contains($ssuKey)) {
        Write-Detail ('Skipping already processed SSU: {0}' -f [IO.Path]::GetFileName($Archive))
        return
    }
    $directory = Join-Path $script:Work ('pkg-' + $script:Counter)
    $script:Counter++
    Expand-Archive $Archive $directory
    $identity = Get-Identity $directory $Archive $InheritedArch
    if ($identity.IsSSU) {
        $identityKey = $identity.PackageName.ToLowerInvariant() + '|' + $identity.PackageVersion + '|' + $identity.Arch
        if (!$script:SeenSsuIdentities.Add($identityKey)) {
            Write-Detail ('Skipping already processed SSU identity: {0}' -f $identity.Folder)
            return
        }
        if ($ssuKey) { [void]$script:SeenSsuNames.Add($ssuKey) }
    }
    $files = @(Get-ChildItem -LiteralPath $directory -File -Force)
    foreach ($file in $files) {
        if ($file.Name -match '(?i)^DesktopDeployment(?:_x86)?\.cab$') { $script:Deployment.Add($file.FullName) }
    }
    # Some packages split payload among CAB parts referenced by *cablist.ini.
    # Those parts belong to this update; they must not become separate KB folders.
    if (@($files | Where-Object { $_.Name -like '*cablist.ini' }).Count -gt 0) {
        $parts = @($files | Where-Object { $_.Extension -eq '.cab' })
        # W10UI expands the complete CAB set in one process. Delta references
        # can cross cabinet boundaries; separate expand calls lose that state.
        $compat = Prepare-LegacyExpander $directory $identity $parts
        if ($compat) { Write-Detail 'Using the update package''s legacy Microsoft dpx.dll.' }
        if ($parts.Count -eq 1) {
            $arguments = @('-r', '-f:*', $parts[0].FullName, $directory)
            if ($compat) { Invoke-Tool $compat $arguments } else { Invoke-CabTool $directory $arguments }
        }
        if ($parts.Count -gt 1) {
            $arguments = @('-f:*', (Join-Path $directory '*.cab'), $directory)
            if ($compat) { Invoke-Tool $compat $arguments } else { Invoke-CabTool $directory $arguments }
        }
        foreach ($part in $parts) {
            Remove-Item -LiteralPath $part.FullName -Force
        }
        foreach ($ini in @($files | Where-Object { $_.Name -like '*cablist.ini' })) { Remove-Item -LiteralPath $ini.FullName -Force }
        $files = @(Get-ChildItem -LiteralPath $directory -File -Force)
    }
    $mum = Test-Path -LiteralPath (Join-Path $directory 'update.mum') -PathType Leaf
    $toc = Test-Path -LiteralPath (Join-Path $directory 'toc.xml') -PathType Leaf
    $children = @()
    if (!$mum -or $toc) {
        $children = @(Get-ChildItem -LiteralPath $directory -File -Recurse -Force | Where-Object { Test-UpdateArchive $_ })
    }
    if ($children.Count -gt 0) {
        $ordered = @($children | Sort-Object @{Expression={ if ($_.Name -match '(?i)^SSU-') { 0 } else { 1 } }}, FullName)
        foreach ($child in $ordered) { Collect-Updates $child.FullName $identity.Arch ($Depth + 1) }
        return
    }
    if ($toc -or (!$mum -and [IO.Path]::GetExtension($Archive) -eq '.msu')) { throw "No update payload found in container: $Archive" }
    $script:Updates.Add([pscustomobject]@{ Archive = $Archive; Directory = $directory; Identity = $identity })
}

function Get-Psf([object]$Update) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($Update.Archive)
    $parent = [IO.Path]::GetDirectoryName($Update.Archive)
    $exact = Join-Path $parent ($stem + '.psf')
    if (Test-Path -LiteralPath $exact -PathType Leaf) { return $exact }
    $kb = $Update.Identity.KB; $arch = $Update.Identity.Arch
    $matches = @(Get-ChildItem -LiteralPath $parent -File -Filter '*.psf' | Where-Object {
        $file = $_
        $kb -and $file.Name -match ('(?i)' + [regex]::Escape($kb) + '(?!\d)') -and
        (!$arch -or (Get-Identity $script:Work $file.FullName '').Arch -eq $arch)
    })
    if ($matches.Count -eq 1) { return $matches[0].FullName }
    throw "Missing or ambiguous PSF companion for $($Update.Archive). Keep its matching .psf alongside the CAB/WIM."
}

function Get-SafePath([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':')) { throw "Invalid payload path: $Relative" }
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (!$path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Payload path escapes extraction directory: $Relative" }
    return $path
}

function Restore-Psf([object]$Update, [string]$Dll) {
    $cix = @(Get-ChildItem -LiteralPath $Update.Directory -File -Filter '*.psf.cix.xml')
    if ($cix.Count -eq 0) { return }
    if ($cix.Count -ne 1) { throw "Ambiguous PSF manifest in $($Update.Archive)" }
    $psf = Get-Psf $Update
    $xml = Read-Xml $cix[0].FullName
    $entries = @($xml.SelectNodes('//*[local-name()="Files"]/*[local-name()="File"]'))
    if ($entries.Count -eq 0) { throw "PSF manifest has no File entries: $($cix[0].FullName)" }
    Write-Detail ('Reconstructing PSF: {0} ({1} files)' -f [IO.Path]::GetFileName($psf), $entries.Count)
    $stream = [IO.File]::OpenRead($psf)
    try {
        foreach ($entry in $entries) {
            $relative = $entry.GetAttribute('name')
            $destination = Get-SafePath $Update.Directory $relative
            if (Test-Path -LiteralPath $destination -PathType Leaf) { continue }
            $source = $entry.SelectSingleNode('./*[local-name()="Delta"]/*[local-name()="Source"]')
            if (!$source) { throw "Missing PSF source entry: $relative" }
            $offset = [long]$source.GetAttribute('offset'); $length = [long]$source.GetAttribute('length')
            if ($offset -lt 0 -or $length -lt 0 -or $length -gt [int]::MaxValue -or $offset -gt ($stream.Length - $length)) { throw "Invalid PSF range: $relative" }
            [void]$stream.Seek($offset, [IO.SeekOrigin]::Begin)
            $buffer = New-Object byte[] ([int]$length)
            $read = 0
            while ($read -lt $buffer.Length) {
                $n = $stream.Read($buffer, $read, $buffer.Length - $read)
                if ($n -eq 0) { throw "Truncated PSF: $psf" }
                $read += $n
            }
            if ($source.GetAttribute('type') -in @('PA30', 'PA31')) { $buffer = [WueNative]::ApplyDelta($Dll, $buffer) }
            # W10UI uses robocopy for paths beyond the .NET Framework limit.
            if ($destination.Length -ge 248) {
                $short = Join-Path $script:Work 'long-path-file'
                [void][IO.Directory]::CreateDirectory($short)
                $filename = [IO.Path]::GetFileName($destination)
                $temporary = Join-Path $short $filename
                [IO.File]::WriteAllBytes($temporary, $buffer)
                if ($entry.HasAttribute('time')) { [IO.File]::SetLastWriteTimeUtc($temporary, [DateTime]::FromFileTimeUtc([long]$entry.GetAttribute('time'))) }
                $log = @(& "$script:SystemBin\robocopy.exe" $short ([IO.Path]::GetDirectoryName($destination)) $filename /MOV /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>&1)
                if ($LASTEXITCODE -ge 8) { throw "Long-path copy failed: $relative`n$($log -join "`n")" }
            } else {
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                [IO.File]::WriteAllBytes($destination, $buffer)
                if ($entry.HasAttribute('time')) { [IO.File]::SetLastWriteTimeUtc($destination, [DateTime]::FromFileTimeUtc([long]$entry.GetAttribute('time'))) }
            }
        }
    } finally { $stream.Dispose() }
}

function Initialize-Native {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class WueNative {
    [DllImport("kernel32.dll", EntryPoint="CreateDirectoryW", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateDirectoryNative(string path, IntPtr securityAttributes);
    public static string CreateWorkDirectory(string root) {
        for (int attempt=0; attempt<128; attempt++) {
            string path=Path.Combine(root, "WUE_" + Guid.NewGuid().ToString("N").Substring(0,4).ToUpper());
            // Reserve the directory atomically; never reuse an existing path.
            if (CreateDirectoryNative(LongPath(path), IntPtr.Zero)) return path;
            int error=Marshal.GetLastWin32Error();
            if (error != 183) throw new Win32Exception(error);
        }
        throw new IOException("Cannot allocate a unique WUE_xxxx temporary directory.");
    }
    static string LongPath(string path) { return path.StartsWith(@"\\?\") ? path : (path.StartsWith(@"\\") ? @"\\?\UNC\" + path.Substring(2) : @"\\?\" + path); }
    [StructLayout(LayoutKind.Sequential)] struct Input { public IntPtr Start; public UIntPtr Size; [MarshalAs(UnmanagedType.Bool)] public bool Editable; }
    [StructLayout(LayoutKind.Sequential)] struct Output { public IntPtr Start; public UIntPtr Size; }
    [UnmanagedFunctionPointer(CallingConvention.Winapi, SetLastError=true)] delegate bool Apply(long flags, Input source, Input delta, out Output target);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate bool Free(IntPtr memory);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll", CharSet=CharSet.Ansi, SetLastError=true)] static extern IntPtr GetProcAddress(IntPtr library, string name);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr library);
    static IntPtr library; static string loaded; static Apply apply; static Free free;
    public static void ReleaseDelta() {
        if (library != IntPtr.Zero) FreeLibrary(library);
        library = IntPtr.Zero; loaded = null; apply = null; free = null;
    }
    public static byte[] ApplyDelta(string dll, byte[] bytes) {
        if (loaded != dll) {
            if (library != IntPtr.Zero) { FreeLibrary(library); library = IntPtr.Zero; loaded = null; }
            library = LoadLibraryEx(dll, IntPtr.Zero, 8);
            if (library == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot load " + dll + "; use a DLL matching the host process architecture.");
            IntPtr a = GetProcAddress(library, "ApplyDeltaB"), f = GetProcAddress(library, "DeltaFree");
            if (a == IntPtr.Zero || f == IntPtr.Zero) throw new Win32Exception();
            apply = (Apply)Marshal.GetDelegateForFunctionPointer(a, typeof(Apply));
            free = (Free)Marshal.GetDelegateForFunctionPointer(f, typeof(Free)); loaded = dll;
        }
        IntPtr memory = Marshal.AllocHGlobal(bytes.Length); Output output = new Output();
        try {
            Marshal.Copy(bytes, 0, memory, bytes.Length);
            Input delta = new Input { Start=memory, Size=new UIntPtr((uint)bytes.Length), Editable=true };
            if (!apply(0, new Input(), delta, out output)) throw new Win32Exception(Marshal.GetLastWin32Error(), "PSF delta reconstruction failed. A compatible UpdateCompression.dll or baseline may be required.");
            byte[] target = new byte[checked((int)output.Size.ToUInt64())];
            if (target.Length != 0) Marshal.Copy(output.Start, target, 0, target.Length);
            return target;
        } finally { Marshal.FreeHGlobal(memory); if (output.Start != IntPtr.Zero) free(output.Start); }
    }
}
'@
}

function Find-Tool([string]$Name) {
    foreach ($path in @((Join-Path $script:ScriptDir $Name), (Join-Path $script:ScriptDir "bin\$Name"))) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    return $null
}

function Find-Wimlib {
    $local = Join-Path $script:ScriptDir 'wimlib-imagex.exe'
    if (Test-Path -LiteralPath $local -PathType Leaf) { return $local }
    # where.exe implements Windows command lookup: current directory, then
    # PATH in order. Do not add a private bin directory or use PowerShell's
    # Get-Command, which normally excludes the current directory.
    $ErrorActionPreference = 'Continue'
    $matches = @(& (Join-Path $script:SystemBin 'where.exe') 'wimlib-imagex.exe' 2>$null)
    if ($LASTEXITCODE -eq 0 -and $matches.Count -gt 0) { return [string]$matches[0] }
    return $null
}

function Get-DeltaDll {
    foreach ($directory in @($script:ScriptDir, (Join-Path $script:ScriptDir 'bin'))) {
        $path = Join-Path $directory 'UpdateCompression.dll'
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Test-HostDll $path)) { return $path }
    }
    # DesktopDeployment DLLs are selected for the PowerShell host, not the update.
    $ddcName = 'DesktopDeployment.cab'
    if (![Environment]::Is64BitProcess) { $ddcName = 'DesktopDeployment_x86.cab' }
    $ddc = @($script:Deployment | Where-Object { [IO.Path]::GetFileName($_) -eq $ddcName })
    foreach ($cab in $ddc) {
        $directory = Join-Path $script:Work ('dll-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($directory)
        Invoke-Tool $script:Expand @('-r', '-f:*', $cab, $directory)
        $path = Join-Path $directory 'UpdateCompression.dll'
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Test-HostDll $path)) { return $path }
    }
    $path = Join-Path $script:SystemBin 'UpdateCompression.dll'
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    return (Join-Path $script:SystemBin 'msdelta.dll')
}

function Test-HostDll([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { return $false }
        $stream.Position = 0x3c; $pe = $reader.ReadInt32()
        $stream.Position = $pe
        if ($reader.ReadUInt32() -ne 0x4550) { return $false }
        $machine = $reader.ReadUInt16()
        switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { return $machine -eq 0x8664 }
            'ARM64' { return $machine -eq 0xaa64 }
            default { return $machine -eq 0x14c }
        }
    } finally { $reader.Dispose() }
}

$script:Work = $null
try {
    $script:ScriptDir = [IO.Path]::GetDirectoryName($env:WUE_SELF)
    $inputFile = Get-Item -LiteralPath $env:WUE_INPUT -Force
    if ($inputFile.PSIsContainer) { throw 'update_file_path must be a file.' }
    if ((Get-Format $inputFile.FullName) -eq 'UNKNOWN') { throw 'Unsupported file: expected a CAB or WIM container (including either MSU format).' }
    $root = $inputFile.DirectoryName
    if ($env:WUE_TARGET) { $root = [IO.Path]::GetFullPath($env:WUE_TARGET) }
    [void][IO.Directory]::CreateDirectory($root)
    Initialize-Native
    $script:Work = [WueNative]::CreateWorkDirectory($root)
    $script:SystemBin = Join-Path $env:SystemRoot 'System32'
    $script:Wimlib = $null
    $script:Expand = Find-Tool 'expand.exe'
    if (!$script:Expand) { throw 'expand.exe is unavailable.' }
    $script:Updates = New-Object 'System.Collections.Generic.List[object]'
    $script:Deployment = New-Object 'System.Collections.Generic.List[string]'
    $script:Counter = 0
    $script:SeenSsuNames = New-Object 'System.Collections.Generic.HashSet[string]'
    $script:SeenSsuIdentities = New-Object 'System.Collections.Generic.HashSet[string]'
    Collect-Updates $inputFile.FullName
    if ($script:Updates.Count -eq 0) { throw 'No updates found.' }
    $planned = @{}
    foreach ($update in $script:Updates) {
        $base = $update.Identity.Folder; $folder = $base; $suffix = 2
        while ($planned.ContainsKey($folder)) { $folder = $base + '-' + $suffix; $suffix++ }
        $planned[$folder] = $true
        $destination = Join-Path $root $folder
        if (Test-Path -LiteralPath $destination) { throw "Output already exists: $destination. Choose another target_path or move that folder first." }
        $update | Add-Member NoteProperty Destination $destination
    }
    $dll = $null
    if (@($script:Updates | Where-Object { @(Get-ChildItem -LiteralPath $_.Directory -File -Filter '*.psf.cix.xml').Count -gt 0 }).Count -gt 0) { $dll = Get-DeltaDll }
    try { foreach ($update in $script:Updates) { Restore-Psf $update $dll } }
    finally { [WueNative]::ReleaseDelta() }
    # Publish only after every update has been fully extracted/reconstructed.
    foreach ($update in $script:Updates) {
        [IO.Directory]::Move($update.Directory, $update.Destination)
        Write-Host ('Output: {0}' -f $update.Destination)
    }
    if ($env:WUE_EXPORTINFO -eq '1') { Export-UpdateInfo $script:Updates (Get-Location).ProviderPath }
    # Only the unique directory created by this run may be recursively removed.
    $expected = [IO.Path]::GetFullPath((Join-Path $root ([IO.Path]::GetFileName($script:Work))))
    if ([IO.Path]::GetFullPath($script:Work) -ne $expected -or [IO.Path]::GetFileName($script:Work) -notmatch '^WUE_[0-9a-f]{4}$') { throw 'Unsafe temporary cleanup path.' }
    Remove-Item -LiteralPath $script:Work -Recurse -Force
    $script:Work = $null
    Write-Detail ('Done: {0} update(s).' -f $script:Updates.Count)
    exit 0
} catch {
    [Console]::Error.WriteLine('ERROR: ' + $_.Exception.Message)
    if ($script:Work) { [Console]::Error.WriteLine('Temporary files retained for diagnostics: ' + $script:Work) }
    exit 1
}
