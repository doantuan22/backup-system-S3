param(
    [string]$EnvFile = (Join-Path $PSScriptRoot '..\config\pcbackup.env'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

function Read-EnvFile([string]$Path) {
    $h = @{}
    foreach ($line in Get-Content -Path $Path) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $key = $t.Substring(0, $i).Trim()
        $val = $t.Substring($i + 1).Trim().Trim('"')
        $h[$key] = $val
    }
    return $h
}

if (-not (Test-Path -Path $EnvFile)) {
    Write-Host "Khong tim thay file cau hinh: $EnvFile (sao chep tu pcbackup.env.example)"
    exit 1
}

$cfg = Read-EnvFile -Path $EnvFile
foreach ($k in 'BUCKET', 'PREFIX', 'SOURCE_DIR', 'LOG_DIR') {
    if (-not $cfg.ContainsKey($k) -or $cfg[$k] -eq '') {
        Write-Host "Thieu tham so $k trong $EnvFile"
        exit 1
    }
}
$Remote = if ($cfg.ContainsKey('REMOTE') -and $cfg['REMOTE'] -ne '') { $cfg['REMOTE'] } else { 's3lab' }
$Bucket = $cfg['BUCKET']
$Prefix = $cfg['PREFIX']
$Source = $cfg['SOURCE_DIR']
$LogDir = $cfg['LOG_DIR']

if (-not (Test-Path -Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$DateStr = Get-Date -Format 'yyyy-MM-dd'
$RunLog = Join-Path $LogDir "run-$DateStr.log"
$RcloneLog = Join-Path $LogDir "rclone-$DateStr.log"

function Write-Log([int]$Code, [string]$Msg) {
    $line = '{0} | {1} | {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Code, $Msg
    Add-Content -Path $RunLog -Value $line
    Write-Host $line
}

if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
    Write-Log 1 'Khong tim thay rclone trong PATH'
    exit 1
}
if (-not (Test-Path -Path $Source)) {
    Write-Log 1 "Thu muc nguon khong ton tai: $Source"
    exit 1
}

$Target = "${Remote}:${Bucket}/${Prefix}"
$BucketPath = "${Remote}:${Bucket}"
$exitCode = 1
$lock = $null

try {
    # 1. Kiem tra credential voi S3
    Write-Log 0 "Bat dau. Kiem tra credential voi $BucketPath"
    $out = & rclone lsf $BucketPath --max-depth 1 2>&1 | Out-String
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        if ($out -match 'ExpiredToken|InvalidToken|InvalidAccessKeyId|SignatureDoesNotMatch|security token|failed to get shared config profile|NoCredential') {
            Write-Log 2 'Credential het han hoac sai. Cap nhat credential roi chay lai. Khong chay backup.'
            $exitCode = 2
        }
        elseif ($out -match 'no such host|dial tcp|i/o timeout|connection refused|network is unreachable|context deadline') {
            Write-Log 3 'Loi mang. Khong chay backup.'
            $exitCode = 3
        }
        else {
            $short = ($out.Trim() -split "`n")[0]
            Write-Log 1 "Kiem tra ket noi that bai: $short"
            $exitCode = 1
        }
        exit $exitCode
    }

    # 2. Chống chạy đè bằng file khóa độc quyền
    $LockPath = Join-Path $LogDir 'run.lock'
    try {
        $lock = [System.IO.File]::Open($LockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    }
    catch {
        Write-Log 4 'Dang chay ban khac (file khoa dang duoc giu). Thoat.'
        $exitCode = 4
        exit $exitCode
    }

    # 3. Chạy backup rclone
    $rcArgs = @(
        'copy', $Source, $Target,
        '--exclude', '*.tmp',
        '--exclude', '.git/**',
        '--exclude', 'Thumbs.db',
        '--s3-upload-cutoff', '8M',
        '--s3-chunk-size', '8M',
        '--transfers', '4',
        '-v',
        '--log-file', $RcloneLog
    )
    if ($DryRun) { $rcArgs += '--dry-run' }

    Write-Log 0 "Chay: rclone copy $Source -> $Target (chi tiet: $RcloneLog)"
    & rclone @rcArgs
    $rc = $LASTEXITCODE
    if ($rc -eq 0) {
        Write-Log 0 'Backup thanh cong'
        $exitCode = 0
    }
    else {
        Write-Log 1 "Backup that bai, rclone ma thoat $rc"
        $exitCode = 1
    }
}
finally {
    if ($lock) { $lock.Close() }
    Write-Log $exitCode "THOAT MA $exitCode"
}

exit $exitCode
