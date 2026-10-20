[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]*$')]
    [string]$ServerAddress = '160.202.47.74',
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_-]*$')]
    [string]$UserName = 'root',
    [ValidateRange(1, 65535)]
    [int]$Port = 22,
    [string]$RemoteHome = '/root/GTNH_server/World/opencomputers/bcf373d0-1809-4659-9cae-75d28b2b3ad0/home',
    [string]$BackupRoot = '/root/GTNH_server/oc-script-backups',
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OcUpdateFiles {
    param([string]$ProjectRoot)
    $oc = Join-Path $ProjectRoot 'oc'
    $paths = @((Get-ChildItem -LiteralPath $oc -Filter '*.lua' -File)) +
        @((Get-ChildItem -LiteralPath (Join-Path $oc 'lib') -Filter '*.lua' -File))
    if ($paths.Count -eq 0) { throw 'No OC scripts were found.' }
    foreach ($file in ($paths | Sort-Object FullName)) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked files are not supported: $($file.FullName)" }
        if ($file.Name -notmatch '^[A-Za-z0-9_.-]+\.lua$') { throw "Unsupported file name: $($file.Name)" }
        $relative = $file.FullName.Substring($oc.Length + 1).Replace('\', '/')
        [pscustomobject]@{
            Relative = $relative
            ArchivePath = "oc/$relative"
            Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}

function New-OcUpdateRemoteScript {
    param([object[]]$Files, [string]$Archive, [string]$Target, [string]$Backups, [string]$RunId)
    foreach ($path in @($Target, $Backups)) {
        if ($path -notmatch '^/[A-Za-z0-9._/-]+$' -or $path -match '(^|/)\.{1,2}(/|$)' -or $path.Contains('//')) {
            throw 'Remote paths must be absolute ASCII paths without dot segments.'
        }
    }
    if ($Target -notmatch '/opencomputers/([0-9a-fA-F-]{36})/home$') { throw 'RemoteHome must identify an OC filesystem home directory.' }
    $disk = $Matches[1]
    if ($RunId -notmatch '^[A-Za-z0-9-]+$') { throw 'Invalid update identifier.' }
    foreach ($file in $Files) {
        if ($file.Relative -notmatch '^(lib/)?[A-Za-z0-9_.-]+\.lua$' -or $file.Hash -notmatch '^[a-f0-9]{64}$' -or
            $file.ArchivePath -ne "oc/$($file.Relative)") {
            throw 'Invalid upload manifest.'
        }
    }
    $template = @'
set -Eeuo pipefail
umask 077
target='@@TARGET@@'
backup_root='@@BACKUPS@@/@@DISK@@'
run='@@RUN@@'
stage=''
backup=''
files=(@@FILES@@)
cleanup() {
    case "$stage" in /tmp/crop-oc-update.*) rm -rf -- "$stage" ;; esac
}
on_error() {
    code=$?
    trap - ERR
    set +e
    echo '[ERROR] Update failed.' >&2
    if [ -n "$stage" ] && [ -s "$stage/changed" ]; then
        echo '[ROLLBACK] Restoring changed files...' >&2
        while IFS= read -r rel; do
            dest="$target/$rel"
            tmp="$dest.oc-update-$run.tmp"
            rm -f -- "$tmp"
            if [ -f "$backup/files/$rel" ]; then
                cp -p -- "$backup/files/$rel" "$tmp" && mv -f -- "$tmp" "$dest" || echo "[ERROR] Restore manually: $rel" >&2
            else
                rm -f -- "$dest" || echo "[ERROR] Remove manually: $rel" >&2
            fi
        done < "$stage/changed"
    fi
    [ -z "$backup" ] || echo "[BACKUP] $backup" >&2
    exit "$code"
}
trap cleanup EXIT
trap on_error ERR
trap 'false' HUP INT TERM
for command in tar base64 sha256sum mktemp install cp mv chown chmod realpath dirname; do command -v "$command" >/dev/null; done
test -d "$target"
target=$(cd -- "$target" && pwd -P)
backup_root=$(realpath -m -- "$backup_root")
oc_disk=$(dirname -- "$target")
case "$backup_root/" in "$oc_disk/"*) echo 'Backup must be outside the OC filesystem.' >&2; exit 1 ;; esac
if [ -e "$target/lib" ] || [ -L "$target/lib" ]; then test -d "$target/lib" && test ! -L "$target/lib"; fi
for rel in "${files[@]}"; do
    test ! -L "$target/$rel"
    if [ -e "$target/$rel" ]; then test -f "$target/$rel"; fi
done
stage=$(mktemp -d /tmp/crop-oc-update.XXXXXXXX)
: > "$stage/changed"
echo '[1/4] Receiving and checking scripts...'
base64 --decode > "$stage/payload.tar.gz" <<'OC_UPDATE_PAYLOAD'
@@PAYLOAD@@
OC_UPDATE_PAYLOAD
echo '@@ARCHIVE_HASH@@  payload.tar.gz' > "$stage/archive.sha256"
(cd -- "$stage" && sha256sum -c archive.sha256)
tar -xzf "$stage/payload.tar.gz" -C "$stage"
cat > "$stage/source.sha256" <<'OC_UPDATE_SOURCE'
@@SOURCE_HASHES@@
OC_UPDATE_SOURCE
(cd -- "$stage" && sha256sum -c source.sha256)
echo '[2/4] Backing up existing scripts...'
backup="$backup_root/$run"
test ! -e "$backup"
mkdir -p -- "$backup/files/lib"
: > "$backup/existing.txt"
: > "$backup/added.txt"
for rel in "${files[@]}"; do
    if [ -f "$target/$rel" ]; then
        cp -p -- "$target/$rel" "$backup/files/$rel"
        printf '%s\n' "$rel" >> "$backup/existing.txt"
    else
        printf '%s\n' "$rel" >> "$backup/added.txt"
    fi
done
echo '[3/4] Installing scripts...'
mkdir -p -- "$target/lib"
for rel in "${files[@]}"; do
    dest="$target/$rel"
    tmp="$dest.oc-update-$run.tmp"
    printf '%s\n' "$rel" >> "$stage/changed"
    install -m 0644 -- "$stage/oc/$rel" "$tmp"
    if [ -f "$dest" ]; then
        chmod --reference="$dest" -- "$tmp"
        chown --reference="$dest" -- "$tmp"
    else
        chown --reference="$target" -- "$tmp"
    fi
    mv -f -- "$tmp" "$dest"
done
cat > "$stage/installed.sha256" <<'OC_UPDATE_INSTALLED'
@@INSTALLED_HASHES@@
OC_UPDATE_INSTALLED
echo '[4/4] Verifying installed scripts...'
(cd -- "$target" && sha256sum -c "$stage/installed.sha256")
cp -- "$stage/installed.sha256" "$backup/installed.sha256"
printf '[OK] Updated %s scripts.\n[BACKUP] %s\n' "${#files[@]}" "$backup"
echo '[OK] Journals and other files were left unchanged. Restart the OC robot.'
'@
    $payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Archive))
    $payload = ([regex]::Matches($payload, '.{1,76}') | ForEach-Object { $_.Value }) -join "`n"
    $replacements = @{
        '@@TARGET@@' = $Target; '@@BACKUPS@@' = $Backups.TrimEnd('/'); '@@DISK@@' = $disk; '@@RUN@@' = $RunId
        '@@FILES@@' = (($Files | ForEach-Object { "'$($_.Relative)'" }) -join ' ')
        '@@PAYLOAD@@' = $payload
        '@@ARCHIVE_HASH@@' = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
        '@@SOURCE_HASHES@@' = (($Files | ForEach-Object { "$($_.Hash)  $($_.ArchivePath)" }) -join "`n")
        '@@INSTALLED_HASHES@@' = (($Files | ForEach-Object { "$($_.Hash)  $($_.Relative)" }) -join "`n")
    }
    foreach ($key in $replacements.Keys) { $template = $template.Replace($key, $replacements[$key]) }
    # Receive the complete installer before running it; truncated uploads cannot install half a set.
    $bootstrap = @'
set -e
installer=$(mktemp /tmp/crop-oc-installer.XXXXXXXX)
completed=0
finish() {
    rm -f -- "$installer"
    if [ "$completed" != 1 ]; then echo '[ERROR] Installer was not received or did not finish.' >&2; exit 1; fi
}
trap finish EXIT
cat > "$installer" <<'OC_UPDATE_INSTALLER'
@@INSTALLER@@
OC_UPDATE_INSTALLER
bash "$installer"
completed=1
'@
    return $bootstrap.Replace('@@INSTALLER@@', $template).Replace("`r`n", "`n") + "`n"
}

function Invoke-OcScriptUpdate {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $files = @(Get-OcUpdateFiles -ProjectRoot $projectRoot)
    $tar = (Get-Command tar.exe -ErrorAction Stop).Source
    $archive = Join-Path ([IO.Path]::GetTempPath()) ("crop-oc-update-" + [guid]::NewGuid().ToString('N') + '.tar.gz')
    try {
        $paths = @($files | ForEach-Object { $_.ArchivePath })
        & $tar -czf $archive -C $projectRoot -- @paths
        if ($LASTEXITCODE -ne 0) { throw 'Could not package OC scripts.' }
        $run = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script = New-OcUpdateRemoteScript -Files $files -Archive $archive -Target $RemoteHome -Backups $BackupRoot -RunId $run
        Write-Host "服务器: $UserName@$ServerAddress`:$Port"
        Write-Host "机器人目录: $RemoteHome"
        $files | ForEach-Object { Write-Host "  $($_.Relative)" }
        if ($CheckOnly) { Write-Host '本地检查通过，未连接服务器。'; return }
        Write-Host '更新前请先关闭游戏中的机器人电源，完成后重新启动。'
        Write-Host '由 SSH 提示输入密码，输入时不显示字符；本脚本不读取、不保存密码。'
        Write-Host '首次连接请核对服务器 SSH 指纹；不要忽略已有主机密钥变化的提示。'
        $ssh = Join-Path $env:WINDIR 'System32/OpenSSH/ssh.exe'
        if (-not (Test-Path -LiteralPath $ssh)) { $ssh = (Get-Command ssh.exe -ErrorAction Stop).Source }
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $ssh
        $info.Arguments = "-p $Port -o StrictHostKeyChecking=ask -o ConnectTimeout=20 $UserName@$ServerAddress bash -s"
        $info.UseShellExecute = $false
        $info.RedirectStandardInput = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $info
        try {
            if (-not $process.Start()) { throw 'Could not start SSH.' }
            # Send exact ASCII bytes, independent of PowerShell's console encoding or a UTF-8 BOM.
            $inputStream = $process.StandardInput.BaseStream
            $bytes = [Text.Encoding]::ASCII.GetBytes($script)
            try { $inputStream.Write($bytes, 0, $bytes.Length); $inputStream.Flush() } finally { $inputStream.Close() }
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) { throw "SSH/update failed (exit $($process.ExitCode)). See the output above." }
        } finally { $process.Dispose() }
    } finally {
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    }
}

# Dot-sourcing exposes the packager for offline tests without connecting to a server.
if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-OcScriptUpdate } catch { Write-Error $_; exit 1 }
}
