<#
.SYNOPSIS
  Установка и обновление набора навыков 1c-bitrix-cms для Claude Code и Codex (Windows).

.DESCRIPTION
  Раскладка после установки (важно для относительных путей ../../shared):
    <HOME>\skills\<имя-навыка>\SKILL.md
    <HOME>\shared\...

  Быстрый старт (последний релиз с GitHub):
    irm https://raw.githubusercontent.com/vrtalex/1c-bitrix-cms-skill/main/install.ps1 | iex

  Примеры:
    .\install.ps1 -Both
    .\install.ps1 -Claude -Version 1.0.0
    .\install.ps1 -Local -Both        # из текущего клона, без скачивания
    .\install.ps1 -Check              # есть ли обновление
    .\install.ps1 -DryRun -Auto       # показать план без изменений
#>
[CmdletBinding()]
param(
    [switch]$Claude,
    [switch]$Codex,
    [switch]$Both,
    [switch]$Auto,
    [string]$Version,
    [switch]$Local,
    [switch]$Check,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# --- Константы --------------------------------------------------------------
$Repo      = 'vrtalex/1c-bitrix-cms-skill'
$PackName  = '1c-bitrix-cms'
$SkillDirs = @(
    '1c-bitrix-cms',
    '1c-bitrix-cms-setup',
    '1c-bitrix-cms-settings',
    '1c-bitrix-cms-template',
    '1c-bitrix-cms-content',
    '1c-bitrix-cms-seo',
    '1c-bitrix-cms-commerce',
    '1c-bitrix-cms-deploy',
    '1c-bitrix-cms-security',
    '1c-bitrix-cms-quality',
    '1c-bitrix-cms-update',
    '1c-bitrix-cms-rest'
)
$OrchestratorRel = "skills\$PackName\SKILL.md"
$SampleKbRel     = 'shared\kb\00-overview.md'
$VersionMarker   = '.1c-bitrix-cms.version'

$UserProfile = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$ClaudeHome  = Join-Path $UserProfile '.claude'
$CodexHome   = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $UserProfile '.codex' }

# Каталог скрипта (для режима -Local). При запуске через iex $PSScriptRoot пуст.
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# --- Вывод ------------------------------------------------------------------
function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "  OK $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "  ! $m" -ForegroundColor Yellow }

# --- Утилиты версий ---------------------------------------------------------
function Normalize-Version {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ($Value.Trim().TrimStart('v'))
}

function Convert-VersionToTag {
    param([string]$Value)
    $n = Normalize-Version $Value
    if ([string]::IsNullOrWhiteSpace($n)) { return '' }
    return "v$n"
}

function Compare-VersionGreater {
    param([string]$A, [string]$B)
    function ToNum([string]$v) {
        $v = Normalize-Version $v
        $p = ($v -split '\.') + @('0', '0', '0')
        return ('{0:D5}{1:D5}{2:D5}' -f [int]$p[0], [int]$p[1], [int]$p[2])
    }
    return ((ToNum $A) -gt (ToNum $B))
}

function Invoke-WebRequestCompat {
    param([Parameter(Mandatory=$true)][string]$Uri, [string]$OutFile)
    $params = @{ Uri = $Uri }
    if ($PSVersionTable.PSVersion.Major -lt 6) { $params.UseBasicParsing = $true }
    if ($OutFile) { $params.OutFile = $OutFile }
    return Invoke-WebRequest @params
}

# --- Источники версии -------------------------------------------------------
function Get-LocalCloneVersion {
    $f = Join-Path $ScriptDir 'VERSION'
    if (Test-Path -LiteralPath $f) { return (Get-Content -LiteralPath $f -Raw).Trim() }
    return ''
}

function Get-InstalledVersion {
    param([string]$HomeDir)
    $f = Join-Path (Join-Path $HomeDir 'skills') $VersionMarker
    if (Test-Path -LiteralPath $f) { return (Get-Content -LiteralPath $f -Raw).Trim() }
    return ''
}

function Get-LatestReleaseTag {
    try {
        $resp = Invoke-WebRequestCompat -Uri "https://github.com/$Repo/releases/latest"
        $uri = $resp.BaseResponse.ResponseUri.AbsoluteUri
        if ($uri -match '/releases/tag/(?<tag>[^/]+)$') { return $Matches.tag }
    } catch { }
    return ''
}

function Get-MainVersion {
    try {
        $url = "https://raw.githubusercontent.com/$Repo/main/VERSION"
        return (Invoke-WebRequestCompat -Uri $url).Content.Trim()
    } catch { return '' }
}

function Resolve-RemoteVersion {
    $tag = Get-LatestReleaseTag
    if (-not [string]::IsNullOrWhiteSpace($tag)) { return (Normalize-Version $tag) }
    $ver = Get-MainVersion
    if (-not [string]::IsNullOrWhiteSpace($ver)) { return (Normalize-Version $ver) }
    return ''
}

# --- Цели установки ---------------------------------------------------------
function Get-Targets {
    $mode = 'auto'
    if ($Both) { $mode = 'both' }
    elseif ($Claude -and $Codex) { $mode = 'both' }
    elseif ($Claude) { $mode = 'claude' }
    elseif ($Codex) { $mode = 'codex' }
    elseif ($Auto) { $mode = 'auto' }

    $targets = @()
    switch ($mode) {
        'claude' { $targets += @{ Name = 'Claude'; Home = $ClaudeHome } }
        'codex'  { $targets += @{ Name = 'Codex';  Home = $CodexHome } }
        'both'   {
            $targets += @{ Name = 'Claude'; Home = $ClaudeHome }
            $targets += @{ Name = 'Codex';  Home = $CodexHome }
        }
        'auto' {
            if (Test-Path -LiteralPath $ClaudeHome) { $targets += @{ Name = 'Claude'; Home = $ClaudeHome } }
            if ($env:CODEX_HOME -or (Test-Path -LiteralPath (Join-Path $UserProfile '.codex'))) {
                $targets += @{ Name = 'Codex'; Home = $CodexHome }
            }
            if ($targets.Count -eq 0) {
                $targets += @{ Name = 'Claude'; Home = $ClaudeHome }
                $targets += @{ Name = 'Codex';  Home = $CodexHome }
            }
        }
    }
    return $targets
}

# --- Получение исходников (skills/ + shared/) -------------------------------
function Get-Source {
    param([string]$Stage)

    if ($Local) {
        if (-not (Test-Path -LiteralPath (Join-Path $ScriptDir 'skills')) -or
            -not (Test-Path -LiteralPath (Join-Path $ScriptDir 'shared'))) {
            throw "режим -Local: рядом со скриптом нет skills\ и shared\ ($ScriptDir)"
        }
        return $ScriptDir
    }

    $reqVer = Normalize-Version $Version
    if (-not [string]::IsNullOrWhiteSpace($reqVer)) {
        $tag = Convert-VersionToTag $reqVer
    } else {
        $tag = Get-LatestReleaseTag
        if ([string]::IsNullOrWhiteSpace($tag)) { throw "не удалось определить последний релиз $Repo" }
    }

    $zipUrl = "https://github.com/$Repo/archive/refs/tags/$tag.zip"
    $zip = Join-Path $Stage 'pack.zip'
    Write-Step "Скачивание $tag"
    Invoke-WebRequestCompat -Uri $zipUrl -OutFile $zip | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $Stage -Force

    $extracted = Get-ChildItem -LiteralPath $Stage -Directory |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'skills')) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'shared'))
        } | Select-Object -First 1
    if ($null -eq $extracted) { throw 'неожиданная структура архива (нет skills\ и shared\)' }
    return $extracted.FullName
}

# --- Установка в один HOME --------------------------------------------------
function Install-IntoHome {
    param([string]$Name, [string]$HomeDir, [string]$Source, [string]$InstallVersion)

    $destSkills = Join-Path $HomeDir 'skills'
    $destShared = Join-Path $HomeDir 'shared'

    if ($DryRun) {
        Write-Step "[dry-run] ${Name}: $HomeDir"
        foreach ($s in $SkillDirs) {
            Write-Host ("    copy {0} -> {1}" -f (Join-Path (Join-Path $Source 'skills') $s), (Join-Path $destSkills $s))
        }
        Write-Host ("    copy {0} -> {1}" -f (Join-Path $Source 'shared'), $destShared)
        Write-Host ("    write version {0} -> {1}" -f $InstallVersion, (Join-Path $destSkills $VersionMarker))
        return
    }

    Write-Step "${Name}: установка $InstallVersion -> $HomeDir"
    New-Item -ItemType Directory -Path $destSkills -Force | Out-Null

    foreach ($s in $SkillDirs) {
        $srcSkill = Join-Path (Join-Path $Source 'skills') $s
        if (-not (Test-Path -LiteralPath $srcSkill)) { throw "${Name}: в источнике нет навыка $s" }
        $tmp = Join-Path $destSkills (".tmp-$s." + [guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath $srcSkill -Destination $tmp -Recurse -Force
        $final = Join-Path $destSkills $s
        if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Recurse -Force }
        Move-Item -LiteralPath $tmp -Destination $final
    }
    Write-Ok "${Name}: 12 навыков -> $destSkills"

    $tmpShared = "$destShared.tmp." + [guid]::NewGuid().ToString('N')
    Copy-Item -LiteralPath (Join-Path $Source 'shared') -Destination $tmpShared -Recurse -Force
    if (Test-Path -LiteralPath $destShared) { Remove-Item -LiteralPath $destShared -Recurse -Force }
    Move-Item -LiteralPath $tmpShared -Destination $destShared
    Write-Ok "${Name}: база знаний -> $destShared"

    Set-Content -LiteralPath (Join-Path $destSkills $VersionMarker) -Value $InstallVersion -NoNewline

    # Пост-проверка раскладки.
    if (-not (Test-Path -LiteralPath (Join-Path $HomeDir $OrchestratorRel))) {
        throw "${Name}: после установки нет $OrchestratorRel"
    }
    $resolved = Join-Path (Join-Path $HomeDir 'skills') (Join-Path $PackName (Join-Path '..\..' $SampleKbRel))
    if (-not (Test-Path -LiteralPath $resolved)) {
        throw "${Name}: ..\..\shared не разрешается (нет $SampleKbRel)"
    }
    Write-Ok "${Name}: ..\..\shared\kb\00-overview.md разрешается из навыка"
}

# --- Режим -Check -----------------------------------------------------------
function Invoke-Check {
    $localVer = ''
    foreach ($t in (Get-Targets)) {
        $localVer = Get-InstalledVersion -HomeDir $t.Home
        if (-not [string]::IsNullOrWhiteSpace($localVer)) { break }
    }
    if ([string]::IsNullOrWhiteSpace($localVer)) {
        $localVer = Get-LocalCloneVersion
        if ([string]::IsNullOrWhiteSpace($localVer)) { $localVer = 'none' }
    }

    $remoteVer = Resolve-RemoteVersion
    if ([string]::IsNullOrWhiteSpace($remoteVer)) {
        Write-Output 'CHECK_FAILED reason=remote_version_unavailable'
        return
    }

    if ($localVer -eq 'none' -or (Compare-VersionGreater $remoteVer $localVer)) {
        Write-Output "UPDATE_AVAILABLE local=$localVer remote=$remoteVer"
    } else {
        Write-Output "UP_TO_DATE local=$localVer remote=$remoteVer"
    }
}

# --- Основной поток ---------------------------------------------------------
if ($Check) {
    Invoke-Check
    return
}

# Целевая версия установки.
if ($Local) {
    $installVersion = Get-LocalCloneVersion
    if ([string]::IsNullOrWhiteSpace($installVersion)) { $installVersion = '0.0.0' }
} elseif (-not [string]::IsNullOrWhiteSpace($Version)) {
    $installVersion = Normalize-Version $Version
} else {
    $installVersion = Resolve-RemoteVersion
    if ([string]::IsNullOrWhiteSpace($installVersion)) { throw 'не удалось определить версию релиза' }
}

Write-Step "Набор $PackName $installVersion"
if ($Local) { Write-Ok "источник: локальный клон $ScriptDir" }
else { Write-Ok "источник: релиз github.com/$Repo" }

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("bitrix-cms-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null

try {
    if ($DryRun -and -not $Local) {
        $source = "<распакованный релиз $installVersion>"
    } else {
        $source = Get-Source -Stage $stage
    }

    $installed = @()
    foreach ($t in (Get-Targets)) {
        Install-IntoHome -Name $t.Name -HomeDir $t.Home -Source $source -InstallVersion $installVersion
        $installed += "  - $($t.Name): $($t.Home)\skills\ + $($t.Home)\shared\"
    }

    if ($DryRun) {
        Write-Host "`nDry-run: изменения на диск не вносились." -ForegroundColor Yellow
        return
    }

    Write-Host "`nГотово! Набор $PackName $installVersion установлен." -ForegroundColor Green
    Write-Host 'Цели:'
    $installed | ForEach-Object { Write-Host $_ }
    Write-Host "Точка входа: навык $PackName (орхестратор)."
    Write-Host 'Проверка обновлений: .\install.ps1 -Check'
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
