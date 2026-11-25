param([Parameter(Mandatory)][int]$WindowProcessId)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$process = Get-Process -Id $WindowProcessId
$scope = [Windows.Automation.TreeScope]::Descendants
$invoke = [Windows.Automation.InvokePattern]::Pattern

function Get-VyrraWindow {
    $process.Refresh()
    if ($process.HasExited) { throw ('Vyrra exited with native status 0x{0:X8}.' -f $process.ExitCode) }
    if ($process.MainWindowHandle -ne 0) {
        return [Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
    }
}

function Wait-Control([string]$name, [int]$seconds = 60) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $name)
    $deadline = [DateTime]::UtcNow.AddSeconds($seconds)
    do {
        $window = Get-VyrraWindow
        if ($null -ne $window) {
            $control = $window.FindFirst($scope, $condition)
            if ($null -ne $control -and $control.Current.IsEnabled) { return $control }
        }
        Start-Sleep -Milliseconds 350
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Vyrra did not expose the enabled control '$name'."
}

(Wait-Control 'Download speech model').GetCurrentPattern($invoke).Invoke()
$null = Wait-Control 'Start dictation' 240
Write-Output 'The packaged app downloaded and prepared its speech model.'
(Wait-Control 'More audio options').GetCurrentPattern($invoke).Invoke()
$picker = Wait-Control 'Transcribe WAV'
$wav = Join-Path $PSScriptRoot 'blue-notebook.wav'
$fileHelper = Join-Path $PSScriptRoot 'select-file.ps1'
$pickerJob = Start-Process powershell.exe -ArgumentList '-NoProfile','-NonInteractive','-File',"`"$fileHelper`"","`"$wav`"" -PassThru
try {
    $started = [DateTime]::UtcNow
    $picker.GetCurrentPattern($invoke).Invoke()
    if (-not $pickerJob.WaitForExit(40000) -or $pickerJob.ExitCode -ne 0) { throw 'The Windows file picker did not select the prepared sentence.' }
    $transcript = Wait-Control 'Transcript' 150
    $content = $transcript.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value
    if ($content -notmatch 'blue notebook' -or $content -notmatch 'design review') { throw "Unexpected synthetic transcript: $content" }
    Write-Output "The Windows release transcribed the blue notebook and design review phrases in $([math]::Round(([DateTime]::UtcNow - $started).TotalSeconds,1)) seconds including file selection."
    (Wait-Control 'Save to Library').GetCurrentPattern($invoke).Invoke()
    $null = Wait-Control 'Saved on this device.'
    (Wait-Control 'Library').GetCurrentPattern($invoke).Invoke()
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    do {
        $controls = (Get-VyrraWindow).FindAll($scope, [Windows.Automation.Condition]::TrueCondition)
        if ($controls | Where-Object { $_.Current.Name -match 'blue notebook' }) {
            Write-Output 'Saved the decoded transcript and found it in the local library.'
            return
        }
        Start-Sleep -Milliseconds 400
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'The decoded sample did not appear in the local library.'
} finally {
    if (-not $pickerJob.HasExited) { Stop-Process -Id $pickerJob.Id }
}
