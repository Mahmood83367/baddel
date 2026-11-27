# Baddel for the PowerShell command line (PSReadLine 2.0 or later).
# Copyright (c) 2026 Mahmood. Released under the MIT License.
#
# Opt in by adding one line to your PowerShell profile ($PROFILE); use the folder
# you unpacked Baddel into:
#
#   . "C:\Tools\Baddel\shell\baddel.ps1"
#
# Press Ctrl+T once to correct the selected text, or the last word before the
# cursor when nothing is selected. Press it twice quickly to correct the whole
# command line. PSReadLine's own undo (Ctrl+Z) restores the previous text.
# Nothing is ever run or accepted for you: the line stays on the prompt for you
# to review.
#
# Settings, as environment variables set before this script is loaded:
#   BADDEL_KEY              PSReadLine chord (default 'Ctrl+t'); 'none' binds nothing
#   BADDEL_BIN              path of Baddel.exe
#   BADDEL_DOUBLE_PRESS_MS  time allowed for the second press (default 300)
#   BADDEL_HINT             latin | arabic | none: the layout to assume when the text
#                           itself does not decide (default: the active layout)
#
# Functions you can bind yourself: Invoke-BaddelFix, Invoke-BaddelFix -Mode word,
# Invoke-BaddelFix -Mode line.

if (-not (Get-Module PSReadLine)) { return }

$global:BaddelShell = @{
    Exe    = if ($env:BADDEL_BIN) { $env:BADDEL_BIN } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'Baddel.exe' }
    Window = if ($env:BADDEL_DOUBLE_PRESS_MS) { [int]$env:BADDEL_DOUBLE_PRESS_MS } else { 300 }
    Before = $null
    After  = $null
    Clock  = [System.Diagnostics.Stopwatch]::StartNew()
    Time   = [long]0
}

# Corrects the PSReadLine buffer in place. Returns $true when it changed.
function global:Invoke-BaddelApply([string]$Mode) {
    $state = $global:BaddelShell
    $line = $null; $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ([string]::IsNullOrEmpty($line) -or -not (Test-Path -LiteralPath $state.Exe)) { return $false }
    $arguments = "--fix-text --mode $Mode --unit utf16 --cursor $cursor"
    if ($Mode -eq 'word') {
        $start = 0; $length = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$start, [ref]$length)
        if ($start -ge 0 -and $length -gt 0) { $arguments += " --selection $start $length" }
    }
    if ($env:BADDEL_HINT -in 'latin', 'arabic', 'none') { $arguments += " --hint $($env:BADDEL_HINT)" }

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $state.Exe
    $info.Arguments = $arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    try {
        $process = [System.Diagnostics.Process]::Start($info)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.Close()
        $answer = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        $process.Dispose()
    } catch {
        return $false
    }
    $break = $answer.IndexOf("`n")
    if ($break -lt 0 -or $answer.Substring(0, $break) -notmatch '^ok (\d+)$') { return $false }
    $text = $answer.Substring($break + 1)
    $newCursor = [Math]::Min([int]$Matches[1], $text.Length)
    # One Replace, so one Ctrl+Z takes it back.
    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $text)
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($newCursor)
    return $true
}

# One press: selection or last word. A second press within the window, while the
# line is still what the first press left: the whole line instead.
function global:Invoke-BaddelFix([ValidateSet('auto', 'word', 'line')][string]$Mode = 'auto') {
    $state = $global:BaddelShell
    if ($Mode -ne 'auto') { [void](Invoke-BaddelApply $Mode); return }
    $line = $null; $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($null -ne $state.After -and $line -ceq $state.After -and ($state.Clock.ElapsedMilliseconds - $state.Time) -le $state.Window) {
        if ($state.Before -cne $line) {
            # Take the first press back, so one undo later returns to the original.
            [Microsoft.PowerShell.PSConsoleReadLine]::Undo()
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if ($line -cne $state.Before) { [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $state.Before) }
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($state.Before.Length)
        }
        $state.After = $null
        [void](Invoke-BaddelApply 'line')
        return
    }
    [void](Invoke-BaddelApply 'word')
    $after = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$after, [ref]$cursor)
    $state.Before = $line
    $state.After = $after
    $state.Time = $state.Clock.ElapsedMilliseconds
}

$baddelKey = if ($env:BADDEL_KEY) { $env:BADDEL_KEY } else { 'Ctrl+t' }
if ($baddelKey -ne 'none') {
    Set-PSReadLineKeyHandler -Chord $baddelKey -BriefDescription 'BaddelFix' `
        -Description 'Baddel: correct text typed with the wrong keyboard layout (twice: the whole line)' `
        -ScriptBlock { Invoke-BaddelFix }
}
Remove-Variable baddelKey
