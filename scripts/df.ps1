#requires -Version 5.1
<#
.SYNOPSIS
  df.ps1 — обёртка над публичным API DeepFlow для Windows.

.DESCRIPTION
  Учётные данные берутся так же, как в df.sh:
    1) DEEPFLOW_API_URL / DEEPFLOW_API_KEY из окружения;
    2) хранилище df-auth.ps1 (DPAPI, %APPDATA%\DeepFlow).

  Первичная настройка:
    'dfk_...' | powershell -File scripts\df-auth.ps1 set
    powershell -File scripts\df-auth.ps1 url 'https://app.deepflow.example'
    powershell -File scripts\df-auth.ps1 test

.EXAMPLE
  powershell -File scripts\df.ps1 GET /public/projects

.EXAMPLE
  powershell -File scripts\df.ps1 GET /public/projects/1/deployments/42/diagnostics
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)][string]$Method,
  [Parameter(Mandatory, Position = 1)][string]$Path,
  [Parameter(Position = 2)][string]$Body
)

$ErrorActionPreference = 'Stop'
try {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
} catch { }

$authScript = Join-Path $PSScriptRoot 'df-auth.ps1'
if (-not (Test-Path -LiteralPath $authScript)) {
  [Console]::Error.WriteLine('df.ps1: рядом нет df-auth.ps1 — скопируйте весь каталог scripts')
  exit 1
}

$apiKey = (& $authScript key | Select-Object -Last 1)
if ($LASTEXITCODE -ne 0 -or -not $apiKey) {
  [Console]::Error.WriteLine('df.ps1: DeepFlow API key не настроен — попросите пользователя дать ключ и выполните scripts\df-auth.ps1 set')
  exit 1
}
$apiUrl = (& $authScript url | Select-Object -Last 1)

$base = ([string]$apiUrl).Trim().TrimEnd('/')
if ($base -notmatch '/api/v1$') { $base += '/api/v1' }
$url = $base + '/' + $Path.TrimStart('/')

$headers = @{
  Authorization = "Bearer $($apiKey.Trim())"
  Accept        = 'application/json'
}

$params = @{
  Method      = $Method.ToUpperInvariant()
  Uri         = $url
  Headers     = $headers
  ErrorAction = 'Stop'
}
if ($PSVersionTable.PSVersion.Major -lt 6) { $params['UseBasicParsing'] = $true }
if ($Body) {
  $params['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
  $params['ContentType'] = 'application/json'
}

$status = 0
$content = ''

try {
  $response = Invoke-WebRequest @params
  $status = [int]$response.StatusCode
  $content = [string]$response.Content
} catch {
  $exception = $_.Exception
  $responseProp = $exception.PSObject.Properties['Response']
  if (-not $responseProp -or -not $responseProp.Value) {
    [Console]::Error.WriteLine("df.ps1: request failed: $($Method.ToUpperInvariant()) $url")
    [Console]::Error.WriteLine($exception.Message)
    exit 1
  }

  $response = $responseProp.Value
  $status = [int]$response.StatusCode

  # PowerShell 7: HttpResponseMessage, PowerShell 5.1: HttpWebResponse.
  $contentProp = $response.PSObject.Properties['Content']
  if ($contentProp -and $contentProp.Value) {
    $readTask = $contentProp.Value.PSObject.Methods['ReadAsStringAsync']
    if ($readTask) {
      $content = $contentProp.Value.ReadAsStringAsync().GetAwaiter().GetResult()
    }
  }
  if (-not $content -and $response.PSObject.Methods['GetResponseStream']) {
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
    $content = $reader.ReadToEnd()
    $reader.Dispose()
  }
  if (-not $content) { $content = $exception.Message }
}

if ($content) { Write-Output $content }
[Console]::Error.WriteLine("HTTP $status")

if ($status -ge 200 -and $status -lt 300) { exit 0 }
exit 1
