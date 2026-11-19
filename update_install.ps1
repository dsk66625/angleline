param(
    [Parameter(Mandatory)][string] $PackagePath,
    [Parameter(Mandatory)][string] $TargetExe,
    [Parameter(Mandatory)][int] $OldPid,
    [Parameter(Mandatory)][string] $ExpectedSha256,
    [Parameter(Mandatory)][string] $ResultPath
)

$ErrorActionPreference = 'Stop'

function Get-NativeFilePath([string] $path) {
    # Windows PowerShell 5.1 may pass long paths to Win32 without this prefix.
    if ($path.Length -lt 248 -or $path.StartsWith('\\?\')) { return $path }
    if ($path.StartsWith('\\')) { return '\\?\UNC\' + $path.Substring(2) }
    return '\\?\' + $path
}

function Write-UpdateResult([string] $value) {
    [IO.File]::WriteAllText($ResultPath, $value)
}

function Start-InstalledGame {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $exeFile
    $info.WorkingDirectory = Get-NativeFilePath $installDir
    $info.UseShellExecute = $false
    # Antivirus or indexing software may briefly lock a just-restored executable.
    for ($attempt = 0; ; $attempt++) {
        try {
            return [Diagnostics.Process]::Start($info)
        } catch [ComponentModel.Win32Exception] {
            if ($attempt -ge 20 -or $_.Exception.NativeErrorCode -notin @(32, 33)) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
}

function Read-GamePackage([string] $destination) {
    Add-Type -AssemblyName System.IO.Compression
    # Hold the same read-only handle throughout hashing and extraction.
    $inputFile = [IO.File]::Open($PackagePath, 'Open', 'Read', 'Read')
    try {
        $hasher = [Security.Cryptography.SHA256]::Create()
        try {
            $actual = [BitConverter]::ToString($hasher.ComputeHash($inputFile)).Replace('-', '')
        } finally {
            $hasher.Dispose()
        }
        if ($ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$' -or $actual -ne $ExpectedSha256) {
            throw 'Package digest mismatch'
        }
        $inputFile.Position = 0
        $archive = [IO.Compression.ZipArchive]::new($inputFile, 'Read', $true)
        try {
            # Only this root entry is ever read. No archive path becomes a disk path.
            $entries = @($archive.Entries | Where-Object {
                [string]::Equals($_.FullName, 'Angleline.exe', [StringComparison]::OrdinalIgnoreCase)
            })
            if ($entries.Count -ne 1 -or $entries[0].Length -le 0) {
                throw 'Expected one root Angleline.exe'
            }
            $source = $entries[0].Open()
            try {
                $output = [IO.File]::Open($destination, 'CreateNew', 'Write', 'None')
                try {
                    $source.CopyTo($output)
                    $output.Flush($true)
                    if ($output.Length -ne $entries[0].Length) { throw 'Incomplete ZIP entry' }
                } finally {
                    $output.Dispose()
                }
            } finally {
                $source.Dispose()
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        $inputFile.Dispose()
    }
}

$oldGame = $null
$mutex = $null
$ownsMutex = $false
$canRelaunch = $false
$staged = $null
$backup = $null
$rejected = $null
$failure = 'INSTALL_FAILED'
try {
    foreach ($path in @($TargetExe, $PackagePath, $ResultPath)) {
        if (![IO.Path]::IsPathRooted($path)) { throw 'Absolute paths required' }
    }
    $TargetExe = [IO.Path]::GetFullPath($TargetExe)
    $PackagePath = [IO.Path]::GetFullPath($PackagePath)
    $ResultPath = [IO.Path]::GetFullPath($ResultPath)
    if ($ResultPath -eq $TargetExe -or $ResultPath -eq $PackagePath -or $PackagePath -eq $TargetExe) {
        exit 1
    }
    $ResultPath = Get-NativeFilePath $ResultPath
    $PackagePath = Get-NativeFilePath $PackagePath
    $exeFile = Get-NativeFilePath $TargetExe
    # Process.Start on Windows PowerShell cannot reliably relaunch a longer image path.
    if ($TargetExe.Length -ge 260) { throw 'Game executable path too long to restart' }
    if ([IO.Path]::GetFileName($TargetExe) -ne 'Angleline.exe' -or
        ![IO.File]::Exists($exeFile) -or $OldPid -le 0) { throw 'Invalid game target' }
    $installDir = [IO.Path]::GetDirectoryName($TargetExe)

    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $key = [BitConverter]::ToString($hasher.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($TargetExe.ToUpperInvariant()))).Replace('-', '')
    } finally {
        $hasher.Dispose()
    }
    $mutex = [Threading.Mutex]::new($false, "Local\Angleline.Update.$key")
    try {
        $ownsMutex = $mutex.WaitOne(0)
    } catch [Threading.AbandonedMutexException] {
        $ownsMutex = $true
    }
    if (!$ownsMutex) { exit 2 }

    $oldGame = Get-Process -Id $OldPid -ErrorAction SilentlyContinue
    if ($null -ne $oldGame -and !$oldGame.HasExited) {
        $failure = 'GAME_RUNNING'
        try {
            [void]$oldGame.Handle
            if ($oldGame.MainModule.FileName -notin @($TargetExe, $exeFile)) { throw 'PID does not match game' }
        } catch {
            if (!$oldGame.HasExited) { throw }
        }
    }
    $canRelaunch = $true
    $stem = [IO.Path]::Combine($installDir, '.angleline-' + [guid]::NewGuid().ToString('N'))
    $staged = Get-NativeFilePath ($stem + '.new')
    $backup = Get-NativeFilePath ($stem + '.bak')
    $rejected = Get-NativeFilePath ($stem + '.rejected')
    $failure = 'INVALID_PACKAGE'
    try {
        Read-GamePackage $staged
    } catch [UnauthorizedAccessException] {
        $failure = 'INSTALL_FAILED'
        throw
    } catch [IO.IOException] {
        $failure = 'INSTALL_FAILED'
        throw
    }

    $failure = 'INSTALL_FAILED'
    Write-UpdateResult 'READY'
    if ($null -ne $oldGame -and !$oldGame.HasExited -and !$oldGame.WaitForExit(120000)) {
        $failure = 'GAME_RUNNING'
        throw 'Game did not exit'
    }

    # ReplaceFile keeps the original as a sibling backup on the same volume.
    [IO.File]::Replace($staged, $exeFile, $backup, $true)
    $failure = 'LAUNCH_FAILED'
    Write-UpdateResult 'UPDATED'
    $newGame = Start-InstalledGame
    try {
        if ($newGame.WaitForExit(1500) -and $newGame.ExitCode -ne 0) {
            throw 'New game failed during startup'
        }
    } finally {
        $newGame.Dispose()
    }
    try { [IO.File]::Delete($backup) } catch { }
    exit 0
} catch {
    if ($backup -and [IO.File]::Exists($backup)) {
        try {
            if ([IO.File]::Exists($exeFile)) {
                [IO.File]::Replace($backup, $exeFile, $rejected, $true)
            } else {
                [IO.File]::Move($backup, $exeFile)
            }
        } catch {
            # Keep the original backup on disk if Windows refuses restoration.
            $failure = 'RESTORE_FAILED'
            $canRelaunch = $false
        }
    }
    try { Write-UpdateResult $failure } catch { }
    if ($canRelaunch -and ($null -eq $oldGame -or $oldGame.HasExited)) {
        try { (Start-InstalledGame).Dispose() } catch { }
    }
    exit 1
} finally {
    foreach ($file in @($staged, $rejected)) {
        if ($file) { try { [IO.File]::Delete($file) } catch { } }
    }
    if ($null -ne $oldGame) { $oldGame.Dispose() }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
