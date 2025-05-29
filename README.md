# FocusBank

FocusBank is a PowerShell script I wrote to help me stay focused in a world full of distractions. It’s easy to waste hours clicking around, so I needed something simple to keep me on track.

I’ve tried cutting out distractions completely, but that only worked up to a point. Eventually, I had no fun left. What actually helped was structure. When I’m out or in a work setting, focus comes easier. So I made this script to simulate that.

Starting the script means it’s time to focus. Ending it means you’re done for the day.

## Features

- Default focus goal is 8 hours per day. You can change this with `SetDefaultMinutes` or `SetDefaultHours`.
- Change today’s focus goal with `SetTodayMinues` or `SetTodayHours`.
- Add more minutes if you want to push a little further with `AddMinutes` or `AddHours`.
- Subtract minutes if you started late or forgot to start the timer with `SubtractMinutes` or `SubtractHours`.

## Usage

Run the script in PowerShell like this:

```
.\focusbank.ps1
```

Reset the default focus goal

```
.\focusbank.ps1 SetDefaultMinutes 360
.\focusbank.ps1 SetDefaultHours 6
```

Set today's focus goal

```
.\focusbank.ps1 SetTodayMinutes 300
.\focusbank.ps1 SetTodayHours 5
```

Add time

```
.\focusbank.ps1 AddMinutes 60
.\focusbank.ps1 AddHours 1
```

Subtract time
```
.\focusbank.ps1 SubtractMinutes 120
.\focusbank.ps1 SubtractHours 2
```

