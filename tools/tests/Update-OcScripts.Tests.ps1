Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $project 'tools/Update-OcScripts.ps1')

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
function Posix([string]$Path) {
    $Path = [IO.Path]::GetFullPath($Path).Replace('\', '/')
    return '/' + $Path.Substring(0, 1).ToLowerInvariant() + $Path.Substring(2)
}
function Snapshot([string]$Path) {
    return (@(Get-ChildItem -LiteralPath $Path -File -Recurse | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($Path.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash
    }) -join "`n")
}
$git = (Get-Command git.exe).Source
$bash = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $git) '../bin/bash.exe'))
Assert-True (Test-Path -LiteralPath $bash) 'Git Bash is required for offline installer tests.'
$root = Join-Path $project ('mod/build/oc-update-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root
$disk = 'bcf373d0-1809-4659-9cae-75d28b2b3ad0'
$encoding = New-Object Text.UTF8Encoding($false)
function New-Fixture([string]$Name) {
    $robotHome = Join-Path $root "$Name/World/opencomputers/$disk/home"
    $null = New-Item -ItemType Directory -Path (Join-Path $robotHome 'lib') -Force
    foreach ($entry in @{
        'crop_collect.lua' = '-- previous program'
        'lib/crop_site.lua' = '-- previous library'
        'crop_collect.journal' = 'preserve batch record'
        'crop_auto.journal' = 'preserve automatic record'
        'manual.txt' = 'preserve unrelated files'
    }.GetEnumerator()) {
        [IO.File]::WriteAllText((Join-Path $robotHome $entry.Key), $entry.Value, $encoding)
    }
    return $robotHome
}
function Run-Installer([string]$Text, [string]$Name) {
    Assert-True (-not $Text.Contains("`r")) 'Remote scripts must use LF line endings.'
    $file = Join-Path $root "$Name.sh"
    [IO.File]::WriteAllText($file, $Text, $encoding)
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $bash --noprofile --norc (Posix $file) 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $savedPreference
    [IO.File]::WriteAllText((Join-Path $root "$Name.log"), ($output -join "`n"), $encoding)
    return $code
}
$files = @(Get-OcUpdateFiles $project)
Assert-True ($files.Count -ge 7) 'All current OC programs and libraries must be included.'
Assert-True (@($files | Where-Object { $_.Relative -match 'journal|tests|README' }).Count -eq 0) 'Runtime state and tests must not be uploaded.'
$archive = Join-Path $root 'payload.tar.gz'
$paths = @($files | ForEach-Object { $_.ArchivePath })
& tar.exe -czf $archive -C $project -- @paths
Assert-True ($LASTEXITCODE -eq 0) 'Package generation failed.'
$backups = Posix (Join-Path $root 'backups')

$robotHome = New-Fixture 'success'
$script = New-OcUpdateRemoteScript $files $archive (Posix $robotHome) $backups 'success'
Assert-True ((Run-Installer $script 'success') -eq 0) 'Successful update failed; inspect success.log.'
foreach ($file in $files) {
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $robotHome $file.Relative)).Hash.ToLowerInvariant() -eq $file.Hash) "Wrong installed hash: $($file.Relative)"
}
Assert-True ([IO.File]::ReadAllText((Join-Path $robotHome 'crop_auto.journal')) -eq 'preserve automatic record') 'Automatic journal was changed.'
Assert-True ([IO.File]::ReadAllText((Join-Path $robotHome 'crop_collect.journal')) -eq 'preserve batch record') 'Batch journal was changed.'
Assert-True ([IO.File]::ReadAllText((Join-Path $robotHome 'manual.txt')) -eq 'preserve unrelated files') 'Unrelated file was changed.'
$backup = Join-Path $root "backups/$disk/success/files/crop_collect.lua"
Assert-True ([IO.File]::ReadAllText($backup) -eq '-- previous program') 'Backup does not contain the original script.'

$robotHome = New-Fixture 'bad-hash'
$before = Snapshot $robotHome
$bad = @($files | ForEach-Object { [pscustomobject]@{ Relative = $_.Relative; ArchivePath = $_.ArchivePath; Hash = ('0' * 64) } })
$script = New-OcUpdateRemoteScript $bad $archive (Posix $robotHome) $backups 'bad-hash'
Assert-True ((Run-Installer $script 'bad-hash') -ne 0) 'Corrupt source must be rejected.'
Assert-True ((Snapshot $robotHome) -eq $before) 'Corrupt upload changed the target.'

$robotHome = New-Fixture 'rollback'
$before = Snapshot $robotHome
$script = New-OcUpdateRemoteScript $files $archive (Posix $robotHome) $backups 'rollback'
$line = '    mv -f -- "$tmp" "$dest"'
$script = $script.Replace($line + "`n", $line + "`n" + '    if [ "$rel" = "crop_helper_diag.lua" ]; then false; fi' + "`n")
Assert-True ((Run-Installer $script 'rollback') -ne 0) 'Simulated install failure must fail.'
Assert-True ((Snapshot $robotHome) -eq $before) 'Rollback must restore old files and remove newly introduced files.'

$robotHome = New-Fixture 'truncated'
$before = Snapshot $robotHome
$script = New-OcUpdateRemoteScript $files $archive (Posix $robotHome) $backups 'truncated'
$script = $script.Substring(0, [int]($script.Length / 2))
Assert-True ((Run-Installer $script 'truncated') -ne 0) 'Incomplete installer must fail.'
Assert-True ((Snapshot $robotHome) -eq $before) 'Incomplete upload must not install any files.'

$rejected = $false
try { $null = New-OcUpdateRemoteScript $files $archive '/root/../home' $backups 'invalid' } catch { $rejected = $true }
Assert-True $rejected 'Unsafe target paths must be rejected.'

# Verify the Windows native-process input path without launching SSH or making a connection.
$capture = Join-Path $root 'stdin.bin'
$childCode = '$stream = [IO.File]::Create(''' + $capture.Replace("'", "''") + '''); [Console]::OpenStandardInput().CopyTo($stream); $stream.Close()'
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = (Get-Command powershell.exe).Source
$info.Arguments = '-NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
$info.UseShellExecute, $info.RedirectStandardInput = $false, $true
$process = New-Object Diagnostics.Process
$process.StartInfo = $info
$bytes = [Text.Encoding]::ASCII.GetBytes("set -e`n#" + ('A' * 131072) + "`n")
try {
    Assert-True ($process.Start()) 'Cannot start local input-capture process.'
    $inputStream = $process.StandardInput.BaseStream
    try { $inputStream.Write($bytes, 0, $bytes.Length); $inputStream.Flush() } finally { $inputStream.Close() }
    $process.WaitForExit()
    Assert-True ($process.ExitCode -eq 0) 'Local input capture failed.'
} finally { $process.Dispose() }
Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($capture)) -eq [Convert]::ToBase64String($bytes)) 'Native input must preserve exact bytes with no BOM.'
Write-Host 'PASS: packaging, installation, backup, untouched journals, hash failure, rollback, truncated transfer, paths, Windows byte transport.'
Write-Host "Offline logs: $root"
