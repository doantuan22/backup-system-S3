[CmdletBinding()]
param()

$AwsDir   = Join-Path $HOME ".aws"
$CredFile = Join-Path $AwsDir "credentials"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " CAP NHAT AWS CREDENTIALS CHO PROFILE [labrole] "       -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "Huong dan:" -ForegroundColor Yellow
Write-Host " 1. Vao AWS Academy Learner Lab -> Bam 'Start Lab'"
Write-Host " 2. Bam 'AWS Details' -> Chon tab 'AWS CLI' -> Bam 'Show'"
Write-Host " 3. Copy toan bo 3 dong roi dan vao day (Enter de ket thuc):`n"

if (-not (Test-Path $AwsDir)) {
    New-Item -ItemType Directory -Path $AwsDir -Force | Out-Null
}

$RawLines = @()
while ($true) {
    $Line = Read-Host
    if ([string]::IsNullOrWhiteSpace($Line)) { break }
    $RawLines += $Line
}

function Get-CredValue([string[]]$Lines, [string]$Key) {
    foreach ($l in $Lines) {
        if ($l -match "^\s*$Key\s*=\s*(.+)$") { return $Matches[1].Trim() }
    }
    return $null
}

$AccessKey    = Get-CredValue $RawLines "aws_access_key_id"
$SecretKey    = Get-CredValue $RawLines "aws_secret_access_key"
$SessionToken = Get-CredValue $RawLines "aws_session_token"

if (-not $AccessKey -or -not $SecretKey -or -not $SessionToken) {
    Write-Host "[LOI] Thieu mot trong ba gia tri credential bat buoc!" -ForegroundColor Red
    exit 1
}

$NewBlock = "[labrole]`r`n" +
            "aws_access_key_id = $AccessKey`r`n" +
            "aws_secret_access_key = $SecretKey`r`n" +
            "aws_session_token = $SessionToken`r`n"

if (Test-Path $CredFile) {
    $Content = Get-Content $CredFile -Raw
    $Pattern = '(?ms)^\[labrole\].*?(?=^\[|\z)'
    if ($Content -match $Pattern) {
        $Content = [regex]::Replace($Content, $Pattern, { param($m) $NewBlock })
    } else {
        $Content = $Content.TrimEnd() + "`r`n`r`n" + $NewBlock
    }
    [System.IO.File]::WriteAllText($CredFile, $Content, [System.Text.Encoding]::ASCII)
} else {
    [System.IO.File]::WriteAllText($CredFile, $NewBlock, [System.Text.Encoding]::ASCII)
}

Write-Host "`n[OK] Da ghi thanh cong vao $CredFile" -ForegroundColor Green
Write-Host "`nDang kiem tra quyen qua aws sts get-caller-identity..." -ForegroundColor Cyan

try {
    $Identity = aws sts get-caller-identity --profile labrole | ConvertFrom-Json
    Write-Host "-> Xac thuc thanh cong!" -ForegroundColor Green
    Write-Host "   Account ID : $($Identity.Account)" -ForegroundColor White
    Write-Host "   ARN        : $($Identity.Arn)"     -ForegroundColor White
} catch {
    Write-Host "[THAT BAI] Khong the lay thong tin Account qua profile labrole. Vui long kiem tra lai credential!" -ForegroundColor Red
    exit 1
}
