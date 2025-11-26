$SaveFileName = "focusbank_data.json" 
$SaveFilePath = Join-Path -Path $PSScriptRoot -ChildPath $SaveFileName 
$HardcodedDefaultMins = 4 * 60 

# how many minutes to start with for the current day/session
$CurrentDayStartMins = $HardcodedDefaultMins
# when the script was last ran
$LastRun = (Get-Date).Date
# current streak count
$Streak = 0
# when the streak was last updated
$LastStreakUpdate = $null
# seconds remaining in the current session
$StoredSecs = $null
$JsonData = $null

$SetDefaultMinutes = -1
$SetDefaultHours = -1
$SetTodayMinutes = -1
$SetTodayHours = -1
$AddMinutes = 0
$AddHours = 0
$SubtractMinutes = 0
$SubtractHours = 0

function Show-Menu {
    Clear-Host
    Write-Host "=== Focus Bank Menu ===" -ForegroundColor Cyan
    Write-Host "1. Start Timer (with current settings)"
    Write-Host "2. Set Default Time (saved for future sessions)"
    Write-Host "3. Set Today's Time (this session only)"
    Write-Host "4. Add Time to Current Session"
    Write-Host "5. Subtract Time from Current Session"
    Write-Host "6. View Current Status"
    Write-Host "7. Exit"
    Write-Host ""
}

function Get-MenuChoice {
    do {
        $choice = Read-Host "Select an option (1-7)"
        if ($choice -match '^[1-7]$') {
            return $choice
        }
        Write-Host "Invalid choice. Please enter 1-7." -ForegroundColor Red
    } while ($true)
}

# save default time and optionally adjust remaining time if needed
function Save-Configuration {
    param(
        $NewDefaultMins,
        $CurrentRemainingSecs = -1
    )
    
    try {
        $existingData = @{
        }
        if (Test-Path $SaveFilePath) {
            $jsonObj = Get-Content $SaveFilePath | ConvertFrom-Json
            if ($jsonObj) {
                $jsonObj.PSObject.Properties | ForEach-Object { $existingData[$_.Name] = $_.Value }
            }
        }

        $existingData.ConfiguredInitialMinutes = [int]$NewDefaultMins

        if ($CurrentRemainingSecs -ge 0) {
            $newDefaultSecs = $NewDefaultMins * 60
            if ($CurrentRemainingSecs -gt $newDefaultSecs) {
                $existingData.RemainingMinutes = [int]$NewDefaultMins
            } else {
                $existingData.RemainingMinutes = [int][Math]::Ceiling($CurrentRemainingSecs / 60)
            }
        } else {
            if (-not $existingData.ContainsKey('RemainingMinutes')) { 
                $existingData.RemainingMinutes = [int]$NewDefaultMins 
            }
        }
        
        if (-not $existingData.ContainsKey('LastRunDate')) { $existingData.LastRunDate = $null }
        if (-not $existingData.ContainsKey('Streak')) { $existingData.Streak = 0 }
        if (-not $existingData.ContainsKey('LastStreakUpdateDate')) { $existingData.LastStreakUpdateDate = $null }

        $existingData | ConvertTo-Json | Set-Content -Path $SaveFilePath -Force
        return $true
    } catch {
        Write-Warning "Failed to save configuration: $($_.Exception.Message)"
        return $false
    }
}

function Set-DefaultTime {
    Write-Host "`nSet Default Time (saved for future sessions)" -ForegroundColor Yellow
    Write-Host "1. Set in hours"
    Write-Host "2. Set in minutes"
    $choice = Read-Host "Choose option (1-2)"
    
    $currentRemainingSecs = if (Test-Path $SaveFilePath) {
        try {
            $tempData = Get-Content $SaveFilePath | ConvertFrom-Json
            if ($null -ne $tempData.RemainingMinutes) {
                $tempData.RemainingMinutes * 60
            } else { -1 }
        } catch { -1 }
    } else { -1 }
    
    if ($choice -eq "1") {
        do {
            [int]$hours = Read-Host "Enter hours (positive number)"
            if ($hours -match '^\d+$' -and $hours -gt 0) {
                $minutes = $hours * 60
                $script:SetDefaultHours = $hours
                $script:SetDefaultMinutes = -1

                if (Save-Configuration -NewDefaultMins $minutes -CurrentRemainingSecs $currentRemainingSecs) {
                    Write-Host "Default time set to $hours hours." -ForegroundColor Green
                } else {
                    Write-Host "Default time save failed." -ForegroundColor Yellow
                }
                return
            }

            Write-Host "Please enter a positive number." -ForegroundColor Red
        } while ($true)
    } elseif ($choice -eq "2") {
        do {
            [int]$minutes = Read-Host "Enter minutes (positive number)"
            if ($minutes -match '^\d+$' -and $minutes -gt 0) {
                $script:SetDefaultMinutes = $minutes
                $script:SetDefaultHours = -1

                if (Save-Configuration -NewDefaultMins $minutes -CurrentRemainingSecs $currentRemainingSecs) {
                    Write-Host "Default time set to $minutes minutes." -ForegroundColor Green
                } else {
                    Write-Host "Default time save failed." -ForegroundColor Yellow
                }
                return
            }

            Write-Host "Please enter a positive number." -ForegroundColor Red
        } while ($true)
    } else {
        Write-Host "Invalid choice." -ForegroundColor Red
        return
    }
}

function Set-TodayTime {
    Write-Host "`nSet Today's Time (this session only)" -ForegroundColor Yellow
    Write-Host "1. Set in hours"
    Write-Host "2. Set in minutes"
    $choice = Read-Host "Choose option (1-2)"
    
    if ($choice -eq "1") {
        do {
            [int]$hours = Read-Host "Enter hours (positive number)"
            if ($hours -match '^\d+$' -and $hours -gt 0) {
                $script:SetTodayHours = $hours
                $script:SetTodayMinutes = -1

                Write-Host "Today's time set to $hours hours." -ForegroundColor Green
                return
            }

            Write-Host "Please enter a positive number." -ForegroundColor Red
        } while ($true)
    } elseif ($choice -eq "2") {
        do {
            [int]$minutes = Read-Host "Enter minutes (positive number)"
            if ($minutes -match '^\d+$' -and $minutes -gt 0) {
                $script:SetTodayMinutes = $minutes
                $script:SetTodayHours = -1
                Write-Host "Today's time set to $minutes minutes." -ForegroundColor Green
                return
            }

            Write-Host "Please enter a positive number." -ForegroundColor Red
        } while ($true)
    } else {
        Write-Host "Invalid choice." -ForegroundColor Red
        return
    }
}

function Add-Time {
    Write-Host "`nAdd Time to Current Session" -ForegroundColor Yellow
    Write-Host "1. Add hours"
    Write-Host "2. Add minutes"
    $choice = Read-Host "Choose option (1-2)"
    
    if ($choice -eq "1") {
        do {
            [int]$hours = Read-Host "Enter hours to add (positive number)"
            if ($hours -match '^\d+$' -and $hours -gt 0) {
                $script:AddHours = $hours
                Write-Host "Will add $hours hours to current session." -ForegroundColor Green
                return
            }

            Write-Host "Please enter a positive number." -ForegroundColor Red
        } while ($true)
    } elseif ($choice -eq "2") {
        do {
            [int]$minutes = Read-Host "Enter minutes to add (positive number)"
            if ($minutes -match '^\d+$' -and $minutes -gt 0) {
                $script:AddMinutes = $minutes
                Write-Host "Will add $minutes minutes to current session." -ForegroundColor Green
                return
            }
    
            Write-Host "Please enter a positive number." -ForegroundColor Red
        } while ($true)
    } else {
        Write-Host "Invalid choice." -ForegroundColor Red
        return
    }
}

function Remove-Time {
    Write-Host "`nSubtract Time from Current Session" -ForegroundColor Yellow
    Write-Host "1. Subtract hours"
    Write-Host "2. Subtract minutes"
    $choice = Read-Host "Choose option (1-2)"
    
    if ($choice -eq "1") {
        do {
            [int]$hours = Read-Host "Enter hours to subtract (positive number)"
            if ($hours -match '^\d+$' -and $hours -gt 0) {
                $script:SubtractHours = $hours
                Write-Host "Will subtract $hours hours from current session." -ForegroundColor Green
                return
            }

            Write-Host "Please enter a positive number." -ForegroundColor Red
        } while ($true)
    } elseif ($choice -eq "2") {
        do {
            [int]$minutes = Read-Host "Enter minutes to subtract (positive number)"
            if ($minutes -match '^\d+$' -and $minutes -gt 0) {
                $script:SubtractMinutes = $minutes
                Write-Host "Will subtract $minutes minutes from current session." -ForegroundColor Green
                return
            }

            Write-Host "Please enter a positive number." -ForegroundColor Red
        } while ($true)
    } else {
        Write-Host "Invalid choice." -ForegroundColor Red
        return
    }
}
function Show-Status {
    Write-Host "`nCurrent Status:" -ForegroundColor Green
    
    if (Test-Path $SaveFilePath) {
        try {
            $tempJson = Get-Content $SaveFilePath | ConvertFrom-Json
            if ($null -ne $tempJson.ConfiguredInitialMinutes) {
                Write-Host "Default time: $($tempJson.ConfiguredInitialMinutes) minutes"
            }
            if ($null -ne $tempJson.RemainingMinutes) {
                Write-Host "Saved time: $($tempJson.RemainingMinutes) minutes"
            }
            if ($null -ne $tempJson.Streak) {
                Write-Host "Current streak: Day $($tempJson.Streak)"
            }
        } catch {
            Write-Host "Error reading save file details." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No save file found - this will be a new session."
    }
    
    $pendingChanges = @()
    if ($SetDefaultHours -gt 0) { $pendingChanges += "Set default: $SetDefaultHours hours" }
    if ($SetDefaultMinutes -gt 0) { $pendingChanges += "Set default: $SetDefaultMinutes minutes" }
    if ($SetTodayHours -gt 0) { $pendingChanges += "Set today: $SetTodayHours hours" }
    if ($SetTodayMinutes -gt 0) { $pendingChanges += "Set today: $SetTodayMinutes minutes" }
    if ($AddHours -gt 0) { $pendingChanges += "Add: $AddHours hours" }
    if ($AddMinutes -gt 0) { $pendingChanges += "Add: $AddMinutes minutes" }
    if ($SubtractHours -gt 0) { $pendingChanges += "Subtract: $SubtractHours hours" }
    if ($SubtractMinutes -gt 0) { $pendingChanges += "Subtract: $SubtractMinutes minutes" }
    
    if ($pendingChanges.Count -gt 0) {
        Write-Host "`nPending changes for next timer start:" -ForegroundColor Yellow
        $pendingChanges | ForEach-Object { Write-Host "  - $_" }
    }
}

do {
    Show-Menu
    $menuChoice = Get-MenuChoice
    
    switch ($menuChoice) {
        1 { 
            break 
        }
        2 { 
            Set-DefaultTime
            Read-Host "`nPress any key to return to menu"
        }
        3 { 
            Set-TodayTime
            Read-Host "`nPress any key to return to menu"
        }
        4 { 
            Add-Time
            Read-Host "`nPress any key to return to menu"
        }
        5 { 
            Remove-Time
            Read-Host "`nPress any key to return to menu"
        }
        6 { 
            Show-Status
            Read-Host "`nPress any key to return to menu"
        }
        7 { 
            exit 
        }
    }
} while ($menuChoice -ne 1)

if (Test-Path $SaveFilePath) { 
    try { 
        $script:JsonData = Get-Content $SaveFilePath | ConvertFrom-Json 
        
        if ($null -ne $JsonData.ConfiguredInitialMinutes) {
            try {
                if ($JsonData.ConfiguredInitialMinutes -gt 0) {
                    $script:CurrentDayStartMins = $JsonData.ConfiguredInitialMinutes
                } else { Write-Warning "Invalid 'ConfiguredInitialMinutes' ('$($JsonData.ConfiguredInitialMinutes)') in save file." }
            } catch { Write-Warning "Error parsing 'ConfiguredInitialMinutes' ('$($JsonData.ConfiguredInitialMinutes)') from save file. Error: $($_.Exception.Message)" }
        }

        if ($null -ne $JsonData.RemainingMinutes) {
            try {
                if ($JsonData.RemainingMinutes -ge 0) { 
                    $script:StoredSecs = $JsonData.RemainingMinutes * 60 
                } else { Write-Warning "Invalid 'RemainingMinutes' ('$($JsonData.RemainingMinutes)') in save file." }
            } catch { Write-Warning "Error parsing 'RemainingMinutes' ('$($JsonData.RemainingMinutes)') from save file. Error: $($_.Exception.Message)" }
        }

        if ($null -ne $JsonData.LastRunDate) {
            try { 
                $script:LastRun = ([datetime]$JsonData.LastRunDate).Date 
            } catch { Write-Warning "Error parsing 'LastRunDate' ('$($JsonData.LastRunDate)') from save file. Error: $($_.Exception.Message)" }
        }

        if ($null -ne $JsonData.Streak) {
            try {
                if ($JsonData.Streak -ge 0) { 
                    $script:Streak = $JsonData.Streak
                } else { 
                    Write-Warning "Invalid 'Streak' ('$($JsonData.Streak)') in save file." 
                }
            } catch { Write-Warning "Error parsing 'Streak' ('$($JsonData.Streak)') from save file. Error: $($_.Exception.Message)" }
        }

        if ($null -ne $JsonData.LastStreakUpdateDate) {
            try { 
                $script:LastStreakUpdate = ([datetime]$JsonData.LastStreakUpdateDate).Date 
            } catch { Write-Warning "Error parsing 'LastStreakUpdateDate' ('$($JsonData.LastStreakUpdateDate)') from save file. Error: $($_.Exception.Message)" }
        }
    } catch { 
        Write-Warning "Error loading or parsing save data: $($_.Exception.Message)."
        $script:JsonData = $null 
    }
}

$MinsLoadedFromFileOrHardcoded = $CurrentDayStartMins

if ($SetDefaultHours -gt 0) {
    [int]$calculatedMins = $SetDefaultHours * 60
    $script:CurrentDayStartMins = $calculatedMins 
    Write-Host "Daily default setting will be updated to $SetDefaultHours hours."
}

if ($SetDefaultMinutes -gt 0) {
    $script:CurrentDayStartMins = $SetDefaultMinutes 
    Write-Host "Daily default setting will be updated to $SetDefaultMinutes minutes."
}

if ($CurrentDayStartMins -eq $MinsLoadedFromFileOrHardcoded -and `
    $MinsLoadedFromFileOrHardcoded -ne $HardcodedDefaultMins -and `
    $SetTodayMinutes -eq -1 -and $SetTodayHours -eq -1) {
    Write-Host "Using configured daily default (from file): $MinsLoadedFromFileOrHardcoded minutes for new day sessions."
}

if ($SetTodayHours -gt 0) {
    $calculatedMins = $SetTodayHours * 60
    if ($CurrentDayStartMins -ne $calculatedMins) { 
        Write-Host "Override for this session's new day start time: $SetTodayHours hours."
    }

    $CurrentDayStartMins = $calculatedMins
}

if ($SetTodayMinutes -gt 0) {
    if ($CurrentDayStartMins -ne $SetTodayMinutes) { 
        Write-Host "Override for this session's new day start time: $SetTodayMinutes minutes."
    }

    $CurrentDayStartMins = $SetTodayMinutes
}

$CurrentDate = (Get-Date).Date 
$RemainingSeconds = $CurrentDayStartMins * 60

if (($CurrentDate -eq $LastRun)) {
    if ($null -ne $StoredSecs) {
        $RemainingSeconds = $StoredSecs
        Write-Host "Loaded saved session: $([Math]::Ceiling($StoredSecs / 60)) minutes from $($LastRun.ToString('yyyy-MM-dd'))."
    } else {
        $RemainingSeconds = $CurrentDayStartMins * 60
        Write-Host "No previous session for today. Starting with $CurrentDayStartMins minutes."
    }
}

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
    }
    Write-Host "Subtracted $SubtractHours hour(s). New time: $([Math]::Ceiling($RemainingSeconds/60)) min."
}
if ($SubtractMinutes -gt 0) {
    $secsToSubtractFromMinutes = $SubtractMinutes * 60
    if ($RemainingSeconds -ge $secsToSubtractFromMinutes) {
        $RemainingSeconds -= $secsToSubtractFromMinutes
    } else {
        $RemainingSeconds = 0 
    }
    Write-Host "Subtracted $SubtractMinutes minute(s). New time: $([Math]::Ceiling($RemainingSeconds/60)) min."
}

if ($CurrentDate -gt $LastRun) { 
    $duration = $CurrentDayStartMins
    $unit = "minute(s)"
    if (($CurrentDayStartMins % 60) -eq 0 -and $CurrentDayStartMins -ne 0) {
        $duration = $CurrentDayStartMins / 60
        $unit = if ($duration -eq 1) { "hour" } else { "hours" }
    }

    Write-Host "It's a new day ($($CurrentDate.ToString('yyyy-MM-dd')))! Resetting bank to $duration $unit."
}

if ($CurrentDate -gt $LastStreakUpdate) { 
    if ($null -ne $LastStreakUpdate -and $LastStreakUpdate.AddDays(1) -eq $CurrentDate) {
        if ($StoredSecs -gt 0) {
            $script:Streak = 1 
            Write-Host "Day $Streak."
        }
    } else {
        $script:Streak = 1 
        Write-Host "Day $Streak."
    }
    $script:LastStreakUpdate = $CurrentDate 
} else { 
    Write-Host "Day $Streak."
}

try { 
    if ($RemainingSeconds -le 0) { 
        Write-Host "No focus time remaining for today."
        Read-Host "`nPress any key to exit"
    } else { 
        Write-Host "Timer Started. Press Ctrl+C to exit and save." 
        while ($RemainingSeconds -gt 0) { 
            $ts = New-TimeSpan -Seconds $RemainingSeconds 
            Write-Host -NoNewline ("`rRemaining: {0:D2}:{1:D2}:{2:D2}  " -f $ts.Hours, $ts.Minutes, $ts.Seconds) 
            Start-Sleep -Seconds 1 
            $RemainingSeconds--
        }
        $script:Streak++
        Write-Host "`rTime's up! Session complete."
        Read-Host "`nPress any key to exit"
    }
} catch { 
    Write-Warning "Unexpected error during timer."
} finally { 
    $saveMins = [Math]::Ceiling($RemainingSeconds / 60) 
    if ($saveMins -lt 0) { $saveMins = 0 }

    $saveDataObj = @{}
    if (Test-Path $SaveFilePath) {
        try {
            $jsonObj = Get-Content $SaveFilePath | ConvertFrom-Json
            if ($jsonObj) {
                $jsonObj.PSObject.Properties | ForEach-Object { $saveDataObj[$_.Name] = $_.Value }
            }
        } catch {
            # If loading fails, proceed with empty hashtable
        }
    }

    $saveDataObj.RemainingMinutes = $saveMins
    $saveDataObj.LastRunDate = (Get-Date).ToString("o")
    $saveDataObj.Streak = $Streak
    $saveDataObj.LastStreakUpdateDate = $LastStreakUpdate.ToString("o")

    # Ensure ConfiguredInitialMinutes is preserved if it exists
    if (-not $saveDataObj.ContainsKey('ConfiguredInitialMinutes')) { $saveDataObj.ConfiguredInitialMinutes = $null }

    try { 
        $saveDataObj | ConvertTo-Json | Set-Content -Path $SaveFilePath -Force 
    } catch { Write-Error "Failed to save progress to $SaveFilePath : $($_.Exception.Message)" }
}
