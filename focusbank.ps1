param ( 
    [int]$ArgMinutes = -1,
    [int]$SetDefaultMinutes = -1,
    [int]$AddMinutes = 0,
    [int]$SubtractMinutes = 0
)

# --- Constants ---
$SaveFileName = "focusbank_data.json" 
$SaveFilePath = Join-Path -Path $PSScriptRoot -ChildPath $SaveFileName 
$HardcodedDefaultMins = 8 * 60 

# --- State Variable Initialization ---
$CurrentDayStartMins = $HardcodedDefaultMins # Default minutes for a new day in the current session.
$SaveFileDefaultMins = $HardcodedDefaultMins # Default minutes to be saved in the JSON configuration.
# Initialize to yesterday to ensure daily reset logic triggers correctly on first run or if no save file.
$LastRun = (Get-Date).AddDays(-1).Date 
$Streak = 0 
# Initialize to two days ago to ensure streak logic evaluates correctly on first run.
$LastStreakUpdate = (Get-Date).AddDays(-2).Date 
# $PrevDayEndSecs tracks the bank state at the end of the *previous* day for streak logic.
$PrevDayEndSecs = 1 
$JsonData = $null # Holds the parsed content of the save file.

# --- Load Saved State ---
if (Test-Path $SaveFilePath) { 
    try { 
        $JsonData = Get-Content $SaveFilePath | ConvertFrom-Json 
        
        if ($null -ne $JsonData.ConfiguredInitialMinutes) {
            try {
                $cfgMins = [int]$JsonData.ConfiguredInitialMinutes
                if ($cfgMins -gt 0) {
                    $CurrentDayStartMins = $cfgMins 
                    $SaveFileDefaultMins = $cfgMins
                } else { Write-Warning "Invalid 'ConfiguredInitialMinutes' ('$($JsonData.ConfiguredInitialMinutes)') in save file." }
            } catch { Write-Warning "Error parsing 'ConfiguredInitialMinutes' ('$($JsonData.ConfiguredInitialMinutes)') from save file. Error: $($_.Exception.Message)" }
        }

        if ($null -ne $JsonData.RemainingMinutes) {
            try {
                $remMins = [int]$JsonData.RemainingMinutes
                if ($remMins -ge 0) { 
                    $PrevDayEndSecs = $remMins * 60 
                } else { Write-Warning "Invalid 'RemainingMinutes' ('$remMins') in save file (negative value). Value ignored for PrevDayEndSecs." }
            } catch { Write-Warning "Error parsing 'RemainingMinutes' ('$($JsonData.RemainingMinutes)') from save file. Error: $($_.Exception.Message)" }
        }
        if ($null -ne $JsonData.LastRunDate) {
            try { $LastRun = ([datetime]$JsonData.LastRunDate).Date }
            catch { Write-Warning "Error parsing 'LastRunDate' ('$($JsonData.LastRunDate)') from save file. Error: $($_.Exception.Message)" }
        }

        if ($null -ne $JsonData.Streak) {
            try {
                $streakVal = [int]$JsonData.Streak
                if ($streakVal -ge 0) { $Streak = $streakVal }
                else { Write-Warning "Invalid 'Streak' ('$streakVal') in save file (negative value). Value ignored." }
            } catch { Write-Warning "Error parsing 'Streak' ('$($JsonData.Streak)') from save file. Error: $($_.Exception.Message)" }
        }
        if ($null -ne $JsonData.LastStreakUpdateDate) {
            try { $LastStreakUpdate = ([datetime]$JsonData.LastStreakUpdateDate).Date }
            catch { Write-Warning "Error parsing 'LastStreakUpdateDate' ('$($JsonData.LastStreakUpdateDate)') from save file. Using default. Error: $($_.Exception.Message)" }
        }
    } catch { 
        Write-Warning "Error loading or parsing save data: $($_.Exception.Message). Using defaults."
        $JsonData = $null 
    }
}

# --- Process Command-Line Arguments for Defaults ---
# $MinsLoadedFromFileOrHardcoded captures the state of CurrentDayStartMins after file load, before CLI args might change it.
$MinsLoadedFromFileOrHardcoded = $CurrentDayStartMins 

if ($SetDefaultMinutes -gt 0) {
    $SaveFileDefaultMins = $SetDefaultMinutes
    $CurrentDayStartMins = $SetDefaultMinutes # New default also applies to current session if it's a new day.
    Write-Host "Daily default setting will be updated to $SetDefaultMinutes minutes upon saving."
}

# Announce if using a default loaded from file, provided it wasn't just overridden by SetDefaultMinutes and won't be by ArgMinutes.
if ($CurrentDayStartMins -ne $HardcodedDefaultMins -and $CurrentDayStartMins -eq $MinsLoadedFromFileOrHardcoded -and $ArgMinutes -eq -1) { 
    Write-Host "Using configured daily default (from file): $CurrentDayStartMins minutes."
}

if ($ArgMinutes -gt 0) { 
    if ($CurrentDayStartMins -ne $ArgMinutes) { 
        Write-Host "Command-line override for this session's daily default: $ArgMinutes minutes."
    }
    $CurrentDayStartMins = $ArgMinutes # ArgMinutes overrides the daily default for this session if it's a new day.
} elseif ($ArgMinutes -ne -1) { 
    Write-Warning "Invalid command-line value for ArgMinutes: '$ArgMinutes'. Using daily default of $CurrentDayStartMins minutes."
}

# --- Determine Current Session Time ---
$CurrentDate = (Get-Date).Date 
$RemainingSeconds = $CurrentDayStartMins * 60 # Default for a new day.

if (($CurrentDate -eq $LastRun)) { # Same day as last run.
    if ($null -ne $JsonData -and $null -ne $JsonData.RemainingMinutes) {
        try {
            # Load remaining minutes from the saved session for today.
            $loadedMins = [int]$JsonData.RemainingMinutes
            if ($loadedMins -lt 0) { 
                Write-Warning "Loaded 'RemainingMinutes' ('$loadedMins') for current session is negative. Resetting to 0."
                $loadedMins = 0
            }
            $RemainingSeconds = $loadedMins * 60
            Write-Host "Loaded saved session: $loadedMins minutes from $($LastRun.ToString('yyyy-MM-dd'))."
        } catch {
             Write-Warning "Error parsing 'RemainingMinutes' ('$($JsonData.RemainingMinutes)') for current session. Using daily default for session time."
        }
    }
}

# --- Apply Time Adjustments ---
if ($AddMinutes -gt 0) {
    $RemainingSeconds += ($AddMinutes * 60)
    Write-Host "Added $AddMinutes minutes. New time: $([Math]::Ceiling($RemainingSeconds/60)) min."
}
if ($SubtractMinutes -gt 0) {
    $secsToSubtract = $SubtractMinutes * 60
    if ($RemainingSeconds -ge $secsToSubtract) {
        $RemainingSeconds -= $secsToSubtract
    } else {
        $RemainingSeconds = 0 # Prevent negative time.
        Write-Warning "Tried to subtract $SubtractMinutes min, but less available. Time set to 0."
    }
    Write-Host "Subtracted $SubtractMinutes minutes. New time: $([Math]::Ceiling($RemainingSeconds/60)) min."
}

# --- Initial Status Messages ---
if (-not (Test-Path $SaveFilePath)) {
    Write-Host "No save file found. Starting new session with $CurrentDayStartMins minutes default."
}

if ($CurrentDate -gt $LastRun) { 
    $duration = $CurrentDayStartMins
    $unit = "minute(s)"
    if (($CurrentDayStartMins % 60) -eq 0) {
        $duration = $CurrentDayStartMins / 60
        $unit = if ($duration -eq 1) { "hour" } else { "hours" }
    }
    Write-Host "It's a new day ($($CurrentDate.ToString('yyyy-MM-dd')))! Resetting bank to $duration $unit."
} elseif ($RemainingSeconds -le 0) { 
    Write-Host "Focus bank empty from session on $($LastRun.ToString('yyyy-MM-dd')). Waiting for new day to reset."
}

# --- Streak Logic ---
if ($CurrentDate -gt $LastStreakUpdate) { 
    if (($LastStreakUpdate.AddDays(1)) -eq $CurrentDate) { 
        if ($PrevDayEndSecs -le 0) { 
            $Streak++ 
            Write-Host "Bank empty on $($LastStreakUpdate.ToString('yyyy-MM-dd')). Streak advanced! Current: $Streak day(s)."
        } else { 
            $Streak = 0 
            Write-Host "Bank not empty on $($LastStreakUpdate.ToString('yyyy-MM-dd')) (had $([Math]::Ceiling($PrevDayEndSecs / 60)) min left). Streak reset."
        }
    } else { 
        $Streak = 0 
        Write-Host "Streak reset (non-consecutive day or first run)."
    }
    $LastStreakUpdate = $CurrentDate 
} else { 
    Write-Host ("Current streak: $Streak day(s)." + $(if ($Streak -eq 0) {" Complete today to advance."} else {""}))
}

# --- Timer Execution ---
try { 
    if ($RemainingSeconds -le 0) { 
        Write-Host "No focus time remaining for today." 
    } else { 
        Write-Host "Timer Started. Press Ctrl+C to exit and save." 
        while ($RemainingSeconds -gt 0) { 
            $ts = New-TimeSpan -Seconds $RemainingSeconds 
            Write-Host -NoNewline ("`rRemaining: {0:D2}:{1:D2}:{2:D2}  " -f $ts.Hours, $ts.Minutes, $ts.Seconds) 
            Start-Sleep -Seconds 1 
            $RemainingSeconds--
        }
        Write-Host "`rTime's up! Session complete.                      " 
    }
}
catch { Write-Warning "Unexpected error during timer." }
finally { 
    $saveMins = [Math]::Ceiling($RemainingSeconds / 60) 
    if ($saveMins -lt 0) { $saveMins = 0 } 

    $saveDataObj = @{ 
        RemainingMinutes = $saveMins 
        LastRunDate      = (Get-Date).ToString("o") 
        Streak           = $Streak 
        LastStreakUpdateDate = $LastStreakUpdate.ToString("o") 
        ConfiguredInitialMinutes = $SaveFileDefaultMins # Persist the potentially updated daily default.
    }
    
    try { 
        $saveDataObj | ConvertTo-Json | Set-Content -Path $SaveFilePath -Force 
        Write-Host "`nProgress saved: $saveMins minutes. Exiting." 
    } catch { Write-Error "Failed to save progress to $SaveFilePath : $($_.Exception.Message)" }
}
