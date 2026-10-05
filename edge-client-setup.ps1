$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $root 'edge\.env'
$python = Join-Path $root '.edge-venv\Scripts\python.exe'
$port = 8090

if (-not (Test-Path $python)) {
    $systemPython = Get-Command py -ErrorAction SilentlyContinue
    if (-not $systemPython) { $systemPython = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $systemPython) {
        throw 'Python 3.11 or newer is required. Install Python from https://www.python.org/downloads/ and run this file again.'
    }
    Write-Host 'Creating edge Python environment...' -ForegroundColor Cyan
    & $systemPython.Source -m venv (Join-Path $root '.edge-venv')
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the edge Python environment.' }
    & $python -m pip install -q -r (Join-Path $root 'edge\requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Could not install edge gateway dependencies.' }
}

$envDirectory = Split-Path $envFile -Parent
if (-not (Test-Path $envFile)) {
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $newToken = [Convert]::ToBase64String($bytes).Replace('+','').Replace('/','').Replace('=','')
    @(
        "EDGE_CONNECTOR_TOKEN=$newToken"
        'STMS_API_BASE_URL=http://stms-prod-alb-1785449816.ap-south-1.elb.amazonaws.com'
        'MAX_CAMERAS=2'
        'FFMPEG_PATH=ffmpeg'
        'FFPROBE_PATH=ffprobe'
    ) | Set-Content $envFile -Encoding utf8
    Write-Host "Created a new local pairing token in $envFile" -ForegroundColor Cyan
}

$tokenLine = Get-Content $envFile | Where-Object { $_ -match '^EDGE_CONNECTOR_TOKEN=' } | Select-Object -First 1
$token = if ($tokenLine) { ($tokenLine -split '=', 2)[1].Trim() } else { '' }
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'EDGE_CONNECTOR_TOKEN is missing from edge\.env.'
}

$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' |
    Where-Object { $_.NextHop -ne '0.0.0.0' } |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object -First 1
$ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex |
    Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
    Select-Object -ExpandProperty IPAddress -First 1
if ([string]::IsNullOrWhiteSpace($ip)) {
    throw 'Could not find the computer Wi-Fi/LAN IPv4 address.'
}

$url = "http://${ip}:${port}"
$listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if (-not $listening) {
    Start-Process -FilePath $python -ArgumentList '-m','uvicorn','edge.app:app','--host','0.0.0.0','--port',$port -WorkingDirectory $root -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

$health = $null
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    try {
        $health = Invoke-RestMethod "$url/health" -TimeoutSec 3
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}
if (-not $health) {
    throw "Edge gateway did not respond at $url. Check Windows Firewall and confirm both devices use the same Wi-Fi."
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ' STMS EDGE GATEWAY CLIENT CONNECTION DETAILS' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "Edge Gateway URL:  $url" -ForegroundColor Green
Write-Host "Pairing Token:     $token" -ForegroundColor Yellow
Write-Host "Health:             $($health.status)" -ForegroundColor Green
Write-Host ''
Write-Host 'Enter both values in the STMS mobile app under Video jobs > Live IP Camera.' -ForegroundColor White
Write-Host 'The phone and this computer must be on the same Wi-Fi network.' -ForegroundColor White
Write-Host ''
Read-Host 'Press Enter to close'
