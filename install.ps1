# Claude Code Clipboard Hook — Windows installer (PowerShell 5.1+)
# Mirrors install.sh but targets native Windows (no WSL/bash required).

$ErrorActionPreference = "Stop"

$HookDir    = Join-Path $env:USERPROFILE ".claude\hooks"
$Settings   = Join-Path $env:USERPROFILE ".claude\settings.json"
$ClaudeMd   = Join-Path $env:USERPROFILE ".claude\CLAUDE.md"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptName = "copy-code-blocks.py"
$ScriptSrc  = Join-Path $ScriptDir $ScriptName
$ScriptDst  = Join-Path $HookDir $ScriptName

Write-Host "=== Claude Code Clipboard Hook — Install (Windows) ==="
Write-Host ""

# --- Detect Python 3.10+ ---
function Find-Python {
    # Prefer the py launcher (standard with python.org installers).
    foreach ($candidate in @(
        @{ Cmd = "py";     Args = @("-3", "--version") ; HookCmd = "py -3" },
        @{ Cmd = "python"; Args = @("--version")       ; HookCmd = "python" },
        @{ Cmd = "python3";Args = @("--version")       ; HookCmd = "python3" }
    )) {
        if (-not (Get-Command $candidate.Cmd -ErrorAction SilentlyContinue)) { continue }
        $cmdArgs = $candidate.Args
        try {
            $output = & $candidate.Cmd @cmdArgs 2>&1 | Out-String
        } catch {
            continue
        }
        if ($output -match "Python\s+(\d+)\.(\d+)") {
            $major = [int]$Matches[1]
            $minor = [int]$Matches[2]
            if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 10)) {
                return @{ HookCmd = $candidate.HookCmd; Version = "$major.$minor" }
            }
        }
    }
    return $null
}

$python = Find-Python
if ($null -eq $python) {
    Write-Host "ERROR: Python 3.10+ is required but was not found."
    Write-Host "Install from https://www.python.org/downloads/ (make sure 'Add to PATH' is checked)."
    exit 1
}
Write-Host ("Python {0} via '{1}' — OK" -f $python.Version, $python.HookCmd)

# --- Detect clipboard backends ---
Write-Host ""
Write-Host "Clipboard backends:"
$foundBackend = $false
foreach ($cmd in @("copyq", "win32yank", "clip.exe", "clip", "powershell.exe", "pwsh")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Host ("  + {0} (found)" -f $cmd)
        $foundBackend = $true
    }
}
if (-not $foundBackend) {
    Write-Host "  ERROR: No clipboard backend found."
    Write-Host "  clip.exe ships with Windows — your PATH may be broken."
    exit 1
}

# --- Copy hook script ---
if (-not (Test-Path $HookDir)) {
    New-Item -ItemType Directory -Path $HookDir -Force | Out-Null
}
if (-not (Test-Path $ScriptSrc)) {
    Write-Host ("ERROR: source script not found at {0}" -f $ScriptSrc)
    exit 1
}
Copy-Item -Path $ScriptSrc -Destination $ScriptDst -Force
Write-Host ""
Write-Host ("Script installed to {0}" -f $ScriptDst)

# --- Register hook in settings.json ---
$hookCommand = "{0} `"{1}`"" -f $python.HookCmd, $ScriptDst

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

if (-not (Test-Path $Settings)) {
    Write-Utf8NoBom -Path $Settings -Content "{}"
}

# Parse settings.json with -AsHashtable when available (PS 6+), otherwise use PSCustomObject.
$rawSettings = Get-Content -Path $Settings -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($rawSettings)) { $rawSettings = "{}" }

$supportsHashtable = (Get-Command ConvertFrom-Json).Parameters.ContainsKey("AsHashtable")
if ($supportsHashtable) {
    $cfg = $rawSettings | ConvertFrom-Json -AsHashtable
} else {
    # PS 5.1: convert PSCustomObject tree to hashtables so we can mutate it freely.
    # Collections become Generic.List[object] so ConvertTo-Json doesn't collapse
    # single-element arrays into objects (a well-known PS 5.1 quirk).
    function ConvertTo-Hashtable {
        param($obj)
        if ($null -eq $obj) { return $null }
        if ($obj -is [System.Collections.IDictionary]) {
            $h = @{}
            foreach ($k in $obj.Keys) { $h[$k] = ConvertTo-Hashtable $obj[$k] }
            return $h
        }
        if ($obj -is [System.Management.Automation.PSCustomObject]) {
            $h = @{}
            foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hashtable $p.Value }
            return $h
        }
        if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
            $list = New-Object 'System.Collections.Generic.List[object]'
            foreach ($item in $obj) { $null = $list.Add((ConvertTo-Hashtable $item)) }
            return ,$list
        }
        return $obj
    }
    $cfg = ConvertTo-Hashtable ($rawSettings | ConvertFrom-Json)
}
if ($null -eq $cfg) { $cfg = @{} }

if (-not $cfg.ContainsKey("hooks")) { $cfg["hooks"] = @{} }

# Normalize Stop into List[object] so further mutations + ConvertTo-Json behave consistently
# on PS 5.1 (which collapses single-element object[] into a JSON object) and we avoid @() over
# generic lists (which PS sometimes rejects with "Argument types do not match").
$stopList = New-Object 'System.Collections.Generic.List[object]'
if ($cfg["hooks"].ContainsKey("Stop") -and $null -ne $cfg["hooks"]["Stop"]) {
    foreach ($e in $cfg["hooks"]["Stop"]) { $null = $stopList.Add($e) }
}
$cfg["hooks"]["Stop"] = $stopList

$alreadyInstalled = $false
foreach ($entry in $stopList) {
    if ($null -eq $entry) { continue }
    $inner = $entry["hooks"]
    if ($null -eq $inner) { continue }
    foreach ($h in $inner) {
        if ($null -eq $h) { continue }
        if (($h["command"] -as [string]) -and ($h["command"] -like "*copy-code-blocks*")) {
            $alreadyInstalled = $true
            break
        }
    }
    if ($alreadyInstalled) { break }
}

if ($alreadyInstalled) {
    Write-Host "Hook already registered in settings.json — skipping."
} else {
    $innerHooks = New-Object 'System.Collections.Generic.List[object]'
    $null = $innerHooks.Add(@{ type = "command"; command = $hookCommand })
    $null = $stopList.Add(@{ hooks = $innerHooks })

    $json = ($cfg | ConvertTo-Json -Depth 100)
    Write-Utf8NoBom -Path $Settings -Content ($json + "`n")
    Write-Host "Hook registered in settings.json"
}

# --- Offer to add formatting instructions to CLAUDE.md ---
$sectionMarker = "## Claude Code Clipboard Hook"
Write-Host ""
Write-Host "The hook works best when Claude uses fenced code blocks for all commands."
$reply = Read-Host "Add formatting instructions to ${ClaudeMd}? [y/N]"

if ($reply -match "^[Yy]$") {
    $alreadyConfigured = (Test-Path $ClaudeMd) -and ((Get-Content $ClaudeMd -Raw -Encoding UTF8) -match [regex]::Escape($sectionMarker))
    if ($alreadyConfigured) {
        Write-Host "Already configured in CLAUDE.md — skipping."
    } else {
        $claudeDir = Split-Path -Parent $ClaudeMd
        if (-not (Test-Path $claudeDir)) {
            New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
        }
        $existing = ""
        if (Test-Path $ClaudeMd) {
            $existing = Get-Content $ClaudeMd -Raw -Encoding UTF8
            if (-not $existing) { $existing = "" }
        }
        if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) {
            $existing += "`n"
        }
        $section = @'

## Claude Code Clipboard Hook
- Always use fenced code blocks (```) for commands and code the user should copy or run.
- Never use inline code (`) for commands — only for referencing names in prose.
- Every command the user should run MUST be in its own fenced code block on a separate line — never embedded in a sentence or bullet point.
'@
        Write-Utf8NoBom -Path $ClaudeMd -Content ($existing + $section + "`n")
        Write-Host "Formatting instructions added to $ClaudeMd"
    }
} else {
    Write-Host "Skipped — you can add them manually later."
}

Write-Host ""
Write-Host "=== Installation complete ==="
Write-Host "Restart Claude Code to activate the hook."
Write-Host "Every code block from Claude's responses will be copied to your clipboard."
