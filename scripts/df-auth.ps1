#requires -Version 5.1
<#
.SYNOPSIS
  df-auth.ps1 — хранение и выдача учётных данных DeepFlow на Windows.

.DESCRIPTION
  Ключ не хранится в Skill и не передаётся аргументом командной строки:
  он читается из stdin и шифруется средствами Windows (DPAPI) под
  текущего пользователя. Файл %APPDATA%\DeepFlow\api-key.dpapi
  бесполезен на другой машине или под другим пользователем.

  Команды:
    set            прочитать ключ из stdin и сохранить (перезаписывает)
    key            напечатать ключ (для df.sh/df.ps1, не для человека)
    url [<url>]    показать или сохранить базовый URL инсталляции
    status         что настроено, откуда берётся ключ (маска)
    test           GET /public/projects — проверка ключа и URL
    rm             удалить сохранённый ключ

  Переопределения окружения (ничего не сохраняют):
    DEEPFLOW_API_KEY, DEEPFLOW_API_KEY_FILE, DEEPFLOW_API_URL
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Command = 'status',
  [Parameter(Position = 1)][string]$Value
)

$ErrorActionPreference = 'Stop'
try {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
} catch { }

$StoreDir = Join-Path $env:APPDATA 'DeepFlow'
$KeyFile = Join-Path $StoreDir 'api-key.dpapi'
$UrlFile = Join-Path $StoreDir 'api-url'
$DefaultUrl = 'http://localhost:8080'

function Write-Note([string]$Text) {
  [Console]::Error.WriteLine("df-auth: $Text")
}

function Get-Url {
  if ($env:DEEPFLOW_API_URL) { return $env:DEEPFLOW_API_URL.Trim() }
  if (Test-Path -LiteralPath $UrlFile) {
    $stored = (Get-Content -LiteralPath $UrlFile -Raw).Trim()
    if ($stored) { return $stored }
  }
  return $DefaultUrl
}

function Get-UrlSource {
  if ($env:DEEPFLOW_API_URL) { return 'env: DEEPFLOW_API_URL' }
  if ((Test-Path -LiteralPath $UrlFile) -and (Get-Content -LiteralPath $UrlFile -Raw).Trim()) {
    return "file: $UrlFile"
  }
  return "default: $DefaultUrl"
}

function Get-ApiKey {
  if ($env:DEEPFLOW_API_KEY) { return $env:DEEPFLOW_API_KEY.Trim() }
  if ($env:DEEPFLOW_API_KEY_FILE) {
    if (-not (Test-Path -LiteralPath $env:DEEPFLOW_API_KEY_FILE)) {
      throw "DEEPFLOW_API_KEY_FILE is not readable: $env:DEEPFLOW_API_KEY_FILE"
    }
    return (Get-Content -LiteralPath $env:DEEPFLOW_API_KEY_FILE -Raw).Trim()
  }
  if (Test-Path -LiteralPath $KeyFile) {
    $secure = Get-Content -LiteralPath $KeyFile -Raw | ConvertTo-SecureString
    return [Net.NetworkCredential]::new('', $secure).Password
  }
  return $null
}

function Get-KeySource {
  if ($env:DEEPFLOW_API_KEY) { return 'env: DEEPFLOW_API_KEY (не сохранён)' }
  if ($env:DEEPFLOW_API_KEY_FILE) { return "file: $env:DEEPFLOW_API_KEY_FILE" }
  if (Test-Path -LiteralPath $KeyFile) { return "DPAPI: $KeyFile" }
  return 'none'
}

function Set-ApiKey([string]$Key) {
  New-Item -ItemType Directory -Force -Path $StoreDir | Out-Null
  $secure = ConvertTo-SecureString -String $Key -AsPlainText -Force
  $encrypted = ConvertFrom-SecureString -SecureString $secure
  Set-Content -LiteralPath $KeyFile -Value $encrypted -NoNewline -Encoding ASCII

  # DPAPI уже привязан к пользователю; ACL убирает доступ остальных учётных
  # записей на случай, если профиль окажется общим.
  try {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $KeyFile /inheritance:r /grant:r "${me}:(F)" | Out-Null
  } catch {
    Write-Note "не удалось выставить ACL на $KeyFile (DPAPI всё равно защищает файл)"
  }
}

function Mask-Secret([string]$Secret) {
  if ($Secret.Length -le 8) { return '***' }
  return $Secret.Substring(0, 4) + '…' + $Secret.Substring($Secret.Length - 4)
}

function Read-IncomingKey {
  if ([Console]::IsInputRedirected) {
    return [Console]::In.ReadToEnd()
  }
  $secure = Read-Host -AsSecureString 'DeepFlow API key (dfk_...)'
  return [Net.NetworkCredential]::new('', $secure).Password
}

function Invoke-ApiProbe([string]$Url, [string]$Key) {
  $base = $Url.TrimEnd('/')
  if ($base -notmatch '/api/v1$') { $base += '/api/v1' }
  $params = @{
    Method      = 'GET'
    Uri         = "$base/public/projects"
    Headers     = @{ Authorization = "Bearer $Key"; Accept = 'application/json' }
    ErrorAction = 'Stop'
  }
  if ($PSVersionTable.PSVersion.Major -lt 6) { $params['UseBasicParsing'] = $true }
  try {
    $response = Invoke-WebRequest @params
    return [int]$response.StatusCode
  } catch {
    $failure = $_.Exception.PSObject.Properties['Response']
    if ($failure -and $failure.Value) {
      return [int]$failure.Value.StatusCode
    }
    return 0
  }
}

switch ($Command.ToLowerInvariant()) {
  'set' {
    $key = Read-IncomingKey
    $key = $key.Trim()
    if (-not $key) { Write-Note 'пустой ключ'; exit 1 }
    if ($key -notmatch '^dfk_[A-Za-z0-9_-]{43}$') {
      Write-Note 'предупреждение: ключ не похож на dfk_<43 символа>, сохраняю как есть'
    }
    Set-ApiKey $key
    Write-Note "ключ сохранён: DPAPI ($KeyFile)"
    exit 0
  }

  'key' {
    $key = Get-ApiKey
    if (-not $key) {
      Write-Note 'ключ не настроен: попросите пользователя дать ключ и выполните df-auth.ps1 set'
      exit 1
    }
    Write-Output $key
    exit 0
  }

  'url' {
    if (-not $Value) {
      Write-Output (Get-Url)
      exit 0
    }
    $url = $Value.TrimEnd('/')
    if ($url -notmatch '^https?://\S+$') {
      Write-Note 'URL должен начинаться с http:// или https://'
      exit 1
    }
    New-Item -ItemType Directory -Force -Path $StoreDir | Out-Null
    Set-Content -LiteralPath $UrlFile -Value $url -NoNewline -Encoding UTF8
    Write-Note "URL сохранён: $url ($UrlFile)"
    exit 0
  }

  'status' {
    Write-Output "URL:  $(Get-Url) [$(Get-UrlSource)]"
    $key = Get-ApiKey
    if (-not $key) {
      Write-Output 'KEY:  не настроен — попросите пользователя дать ключ и выполните set'
      exit 1
    }
    Write-Output "KEY:  настроен, $(Mask-Secret $key) [$(Get-KeySource)]"
    if ($env:DEEPFLOW_API_KEY) {
      Write-Output '      переменная окружения не сохраняется: для постоянного хранения выполните set'
    }
    exit 0
  }

  'test' {
    $key = Get-ApiKey
    if (-not $key) { Write-Note 'ключ не настроен — выполните set'; exit 1 }
    $url = Get-Url
    $code = Invoke-ApiProbe -Url $url -Key $key
    switch ($code) {
      200 { Write-Output "OK: HTTP 200 — ключ и URL рабочие ($url)"; exit 0 }
      401 { Write-Note 'HTTP 401 — ключ недействителен/отозван: попросите новый и повторите set'; exit 1 }
      403 { Write-Note 'HTTP 403 — ключу не хватает scope projects:read, проект вне списка ключа или тариф без API'; exit 1 }
      0 { Write-Note "нет соединения с $url"; exit 1 }
      default { Write-Note "HTTP $code"; exit 1 }
    }
  }

  'rm' {
    Remove-Item -LiteralPath $KeyFile -Force -ErrorAction SilentlyContinue
    Write-Note 'ключ удалён (env-переменные не затрагиваются)'
    exit 0
  }

  default {
    @(
      'usage: df-auth.ps1 <command>',
      '',
      '  set             сохранить ключ из stdin',
      '  key             напечатать ключ (для df.ps1)',
      '  url [<url>]     показать или сохранить базовый URL',
      '  status          состояние настройки (маска ключа)',
      '  test            проверить ключ запросом GET /public/projects',
      '  rm              удалить сохранённый ключ'
    ) | ForEach-Object { Write-Note $_ }
    exit 1
  }
}
