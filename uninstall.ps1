# Claude Code Clipboard Hook — Windows uninstaller (PowerShell 5.1+)
# Mirrors uninstall.sh but targets native Windows.

$ErrorActionPreference = "Stop"

$HookDir    = Join-Path $env:USERPROFILE ".claude\hooks"
$Settings   = Join-Path $env:USERPROFILE ".claude\settings.json"
$ClaudeMd   = Join-Path $env:USERPROFILE ".claude\CLAUDE.md"
$ScriptName = "copy-code-blocks.py"
$ScriptDst  = Join-Path $HookDir $ScriptName
$LogFile    = Join-Path $HookDir "copy-code-blocks.log"

Write-Host "=== Claude Code Clipboard Hook — Uninstall (Windows) ==="
Write-Host ""

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

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

# --- Remove hook from settings.json ---
if (Test-Path $Settings) {
    $rawSettings = Get-Content -Path $Settings -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($rawSettings)) { $rawSettings = "{}" }

    $supportsHashtable = (Get-Command ConvertFrom-Json).Parameters.ContainsKey("AsHashtable")
    if ($supportsHashtable) {
        $cfg = $rawSettings | ConvertFrom-Json -AsHashtable
    } else {
        $cfg = ConvertTo-Hashtable ($rawSettings | ConvertFrom-Json)
    }
    if ($null -eq $cfg) { $cfg = @{} }

    $removed = $false
    if ($cfg.ContainsKey("hooks") -and $cfg["hooks"].ContainsKey("Stop")) {
        $kept = New-Object 'System.Collections.Generic.List[object]'
        $originalCount = 0
        foreach ($entry in $cfg["hooks"]["Stop"]) {
            $originalCount++
            $isOurs = $false
            if ($null -ne $entry -and $null -ne $entry["hooks"]) {
                foreach ($h in $entry["hooks"]) {
                    if ($null -eq $h) { continue }
                    if (($h["command"] -as [string]) -and ($h["command"] -like "*copy-code-blocks*")) {
                        $isOurs = $true
                        break
                    }
                }
            }
            if (-not $isOurs) { $null = $kept.Add($entry) }
        }
        $removed = ($kept.Count -lt $originalCount)
        if ($removed) {
            if ($kept.Count -eq 0) {
                $cfg["hooks"].Remove("Stop") | Out-Null
            } else {
                $cfg["hooks"]["Stop"] = $kept
            }
            if ($cfg["hooks"].Count -eq 0) {
                $cfg.Remove("hooks") | Out-Null
            }
            $json = ($cfg | ConvertTo-Json -Depth 100)
            Write-Utf8NoBom -Path $Settings -Content ($json + "`n")
            Write-Host "Hook removed from settings.json"
        }
    }
    if (-not $removed) {
        Write-Host "Hook not found in settings.json — nothing to remove."
    }
}

# --- Remove hook script ---
if (Test-Path $ScriptDst) {
    Remove-Item -Path $ScriptDst -Force
    Write-Host ("Script removed from {0}" -f $ScriptDst)
} else {
    Write-Host ("Script not found at {0} — nothing to remove." -f $ScriptDst)
}

# --- Remove log files ---
foreach ($f in @($LogFile, "$LogFile.1")) {
    if (Test-Path $f) {
        Remove-Item -Path $f -Force
        Write-Host ("Log removed: {0}" -f $f)
    }
}

# --- Remove formatting instructions from CLAUDE.md ---
$sectionMarker = "## Claude Code Clipboard Hook"
if ((Test-Path $ClaudeMd) -and ((Get-Content $ClaudeMd -Raw -Encoding UTF8) -match [regex]::Escape($sectionMarker))) {
    $content = Get-Content $ClaudeMd -Raw -Encoding UTF8
    # Remove the section: from "## Claude Code Clipboard Hook" to the next "## " or end of file.
    $pattern = '(?s)\n*## Claude Code Clipboard Hook\n.*?(?=\n## |\Z)'
    $cleaned = [regex]::Replace($content, $pattern, "").TrimEnd()

    if ($cleaned.Length -gt 0) {
        Write-Utf8NoBom -Path $ClaudeMd -Content ($cleaned + "`n")
        Write-Host ("Formatting instructions removed from {0}" -f $ClaudeMd)
    } else {
        Remove-Item -Path $ClaudeMd -Force
        Write-Host ("CLAUDE.md was empty after removal — deleted {0}" -f $ClaudeMd)
    }
} else {
    Write-Host "No formatting instructions found in CLAUDE.md — nothing to remove."
}

Write-Host ""
Write-Host "=== Uninstall complete ==="
Write-Host "Restart Claude Code to apply changes."
