param ( 
    [int]$SetTodayMinutes = -1,
    [int]$SetDefaultMinutes = -1,
    [int]$AddMinutes = 0,
    [int]$SubtractMinutes = 0,
    [int]$SetDefaultHours = -1,
    [int]$SetTodayHours = -1,
    [int]$AddHours = 0,
    [int]$SubtractHours = 0
)

# Constants
$SaveFileName = "focusbank_data.json" 
$SaveFilePath = Join-Path -Path $PSScriptRoot -ChildPath $SaveFileName 
$HardcodedDefaultMins = 8 * 60 

# State Variable Initialization
$CurrentDayStartMins = $HardcodedDefaultMins 
$SaveFileDefaultMins = $HardcodedDefaultMins 
$LastRun = (Get-Date).AddDays(-1).Date # Initialize to yesterday to ensure daily reset logic triggers correctly.
$Streak = 0 
$LastStreakUpdate = (Get-Date).AddDays(-2).Date # Initialize to two days ago for correct streak evaluation on first run.
$StoredSecs = 1 # Default to non-zero to distinguish from an actual empty bank for streak logic on first run.
$JsonData = $null

# Load Saved State
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
                    $StoredSecs = $remMins * 60 
                } else { Write-Warning "Invalid 'RemainingMinutes' ('$remMins') in save file (negative value). Value ignored for StoredSecs." }
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

# Process Command-Line Arguments
# $MinsLoadedFromFileOrHardcoded captures $CurrentDayStartMins state after file load, before CLI modifications.
$MinsLoadedFromFileOrHardcoded = $CurrentDayStartMins 

# Apply CLI arguments for the default time to be saved ($SaveFileDefaultMins).
# These also provisionally set $CurrentDayStartMins (new day default for this session), unless overridden by SetToday* args.
if ($SetDefaultHours -gt 0) {
    $calculatedMins = $SetDefaultHours * 60
    $SaveFileDefaultMins = $calculatedMins
    $CurrentDayStartMins = $calculatedMins 
    Write-Host "Daily default setting will be updated to $SetDefaultHours hours upon saving."
} elseif ($SetDefaultHours -ne -1) {
    Write-Warning "Invalid command-line value for SetDefaultHours: '$SetDefaultHours'. This parameter is ignored for default setting."
}

if ($SetDefaultMinutes -gt 0) { # Takes precedence over SetDefaultHours for $SaveFileDefaultMins
    $SaveFileDefaultMins = $SetDefaultMinutes
    $CurrentDayStartMins = $SetDefaultMinutes 
    Write-Host "Daily default setting will be updated to $SetDefaultMinutes minutes upon saving."
} elseif ($SetDefaultMinutes -ne -1) {
    Write-Warning "Invalid command-line value for SetDefaultMinutes: '$SetDefaultMinutes'. This parameter is ignored for default setting."
}

# Announce if using a file-configured default, if not overridden by SetDefault* or SetToday* CLI args.
if ($CurrentDayStartMins -eq $MinsLoadedFromFileOrHardcoded -and `
    $MinsLoadedFromFileOrHardcoded -ne $HardcodedDefaultMins -and `
    $SetTodayMinutes -eq -1 -and $SetTodayHours -eq -1) {
    Write-Host "Using configured daily default (from file): $MinsLoadedFromFileOrHardcoded minutes for new day sessions."
}

# Apply CLI arguments for *this session's* starting time if it's a new day ($CurrentDayStartMins).
# These override any previously determined $CurrentDayStartMins for the current session only and do NOT affect $SaveFileDefaultMins.
if ($SetTodayHours -gt 0) {
    $calculatedMins = $SetTodayHours * 60
    if ($CurrentDayStartMins -ne $calculatedMins) { 
        Write-Host "Command-line override for this session's new day start time: $SetTodayHours hours."
    }
    $CurrentDayStartMins = $calculatedMins
} elseif ($SetTodayHours -ne -1) {
    Write-Warning "Invalid command-line value for SetTodayHours: '$SetTodayHours'. Using current default of $CurrentDayStartMins minutes for this session's new day start time."
}

if ($SetTodayMinutes -gt 0) { # Takes precedence over SetTodayHours for $CurrentDayStartMins
    if ($CurrentDayStartMins -ne $SetTodayMinutes) { 
        Write-Host "Command-line override for this session's new day start time: $SetTodayMinutes minutes."
    }
    $CurrentDayStartMins = $SetTodayMinutes
} elseif ($SetTodayMinutes -ne -1) {
    Write-Warning "Invalid command-line value for SetTodayMinutes: '$SetTodayMinutes'. Using current default of $CurrentDayStartMins minutes for this session's new day start time."
}

# Determine Current Session Time
$CurrentDate = (Get-Date).Date 
$RemainingSeconds = $CurrentDayStartMins * 60 # Default for a new day, potentially modified by CLI args.

if (($CurrentDate -eq $LastRun)) { # Same day as last run
    $RemainingSeconds = $StoredSecs # Override with saved session time
    Write-Host "Loaded saved session: $([Math]::Ceiling($StoredSecs / 60)) minutes from $($LastRun.ToString('yyyy-MM-dd'))."
}

# Apply Ad-hoc Time Adjustments
if ($AddHours -gt 0) {
    $RemainingSeconds += ($AddHours * 60 * 60)
    Write-Host "Added $AddHours hour(s). New time: $([Math]::Ceiling($RemainingSeconds/60)) min."
}
if ($AddMinutes -gt 0) {
    $RemainingSeconds += ($AddMinutes * 60)
    Write-Host "Added $AddMinutes minute(s). New time: $([Math]::Ceiling($RemainingSeconds/60)) min."
}

if ($SubtractHours -gt 0) {
    $secsToSubtractFromHours = $SubtractHours * 60 * 60
    if ($RemainingSeconds -ge $secsToSubtractFromHours) {
        $RemainingSeconds -= $secsToSubtractFromHours
    } else {
        $RemainingSeconds = 0 
        Write-Warning "Tried to subtract $SubtractHours hour(s), but less available. Time set to 0."
    }
    Write-Host "Subtracted $SubtractHours hour(s). New time: $([Math]::Ceiling($RemainingSeconds/60)) min."
}
if ($SubtractMinutes -gt 0) {
    $secsToSubtractFromMinutes = $SubtractMinutes * 60
    if ($RemainingSeconds -ge $secsToSubtractFromMinutes) {
        $RemainingSeconds -= $secsToSubtractFromMinutes
    } else {
        $RemainingSeconds = 0 
        Write-Warning "Tried to subtract $SubtractMinutes minute(s), but less available. Time set to 0."
    }
    Write-Host "Subtracted $SubtractMinutes minute(s). New time: $([Math]::Ceiling($RemainingSeconds/60)) min."
}

# Initial Status Messages
if (-not (Test-Path $SaveFilePath)) {
    Write-Host "No save file found. Starting new session with $CurrentDayStartMins minutes default."
}

if ($CurrentDate -gt $LastRun) { 
    $duration = $CurrentDayStartMins
    $unit = "minute(s)"
    if (($CurrentDayStartMins % 60) -eq 0 -and $CurrentDayStartMins -ne 0) { # Check for non-zero to avoid "0 hours"
        $duration = $CurrentDayStartMins / 60
        $unit = if ($duration -eq 1) { "hour" } else { "hours" }
    }
    Write-Host "It's a new day ($($CurrentDate.ToString('yyyy-MM-dd')))! Resetting bank to $duration $unit."
} elseif ($RemainingSeconds -le 0) { 
    Write-Host "Waiting for new day to reset."
}

# Streak Logic
if ($CurrentDate -gt $LastStreakUpdate) { 
    if (($LastStreakUpdate.AddDays(1)) -eq $CurrentDate) { # Consecutive day
        if ($StoredSecs -le 0) { # Bank was empty at end of previous tracked day
            $Streak++ 
            Write-Host "Streak advances! Day $Streak."
        } else { 
            $Streak = 0 
            Write-Host "Streak Reset. Day 0."
        }
    } else { # Not a consecutive day or first run after a gap
        $Streak = 0 
        Write-Host "Streak Reset. Day 0."
    }
    $LastStreakUpdate = $CurrentDate 
} else { 
    Write-Host ("Current streak: Day $Streak." + $(if ($Streak -eq 0) {" Complete today to advance."} else {""}))
}

# Timer Execution
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
    if ($saveMins -lt 0) { $saveMins = 0 } # Ensure saved minutes are not negative

    $saveDataObj = @{ 
        RemainingMinutes = $saveMins 
        LastRunDate      = (Get-Date).ToString("o") 
        Streak           = $Streak 
        LastStreakUpdateDate = $LastStreakUpdate.ToString("o") 
        ConfiguredInitialMinutes = $SaveFileDefaultMins 
    }
    
    try { 
        $saveDataObj | ConvertTo-Json | Set-Content -Path $SaveFilePath -Force 
        Write-Host "`nProgress saved: $saveMins minutes. Exiting." 
    } catch { Write-Error "Failed to save progress to $SaveFilePath : $($_.Exception.Message)" }
}
