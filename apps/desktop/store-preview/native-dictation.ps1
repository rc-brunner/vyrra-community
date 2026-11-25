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

function Wait-Control([string]$name, [int]$seconds = 60, [string]$role = '') {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $name)
    if ($role) {
        $type = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::$role)
        $condition = [Windows.Automation.AndCondition]::new($condition, $type)
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($seconds)
    do {
        try {
            $window = Get-VyrraWindow
            if ($null -ne $window) {
                $control = $window.FindFirst($scope, $condition)
                if ($null -ne $control -and $control.Current.IsEnabled) { return $control }
            }
        } catch {
            # Closing the native file picker can disconnect its UI Automation provider.
            # The next poll reacquires the live application window.
            $cause = $_.Exception.GetBaseException()
            if ($cause -isnot [Windows.Automation.ElementNotAvailableException] -and
                $cause.HResult.ToString('X8') -notin @('80040201', '80010012', '80010108')) { throw }
        }
        Start-Sleep -Milliseconds 350
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Vyrra did not expose the enabled control '$name'."
}

function Open-Control($control) {
    Write-Output "Activating $($control.Current.Name) ($($control.Current.ControlType.ProgrammaticName))."
    $pattern = $null
    if ($control.TryGetCurrentPattern($invoke, [ref]$pattern)) { $pattern.Invoke(); return }
    if ($control.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pattern)) { $pattern.Expand(); return }
    $control.SetFocus()
    $focus = [Windows.Automation.AutomationElement]::FocusedElement
    if ($focus.Current.Name -ne $control.Current.Name) { throw 'Focus left the selected Vyrra control.' }
    (New-Object -ComObject WScript.Shell).SendKeys('{ENTER}')
}

Open-Control (Wait-Control 'Download speech model')
$null = Wait-Control 'Start dictation' 240
Write-Output 'The packaged app downloaded and prepared its speech model.'
Open-Control (Wait-Control 'More audio options')
$picker = Wait-Control 'Transcribe WAV'
$wav = Join-Path $PSScriptRoot 'blue-notebook.wav'
$fileHelper = Join-Path $PSScriptRoot 'select-file.ps1'
$pickerJob = Start-Process powershell.exe -ArgumentList '-NoProfile','-NonInteractive','-File',"`"$fileHelper`"","`"$wav`"" -PassThru
try {
    $started = [DateTime]::UtcNow
    Open-Control $picker
    if (-not $pickerJob.WaitForExit(40000) -or $pickerJob.ExitCode -ne 0) { throw 'The Windows file picker did not select the prepared sentence.' }
    $fileSelected = [DateTime]::UtcNow
    $transcript = Wait-Control 'Transcript' 240 'Edit'
    $content = $transcript.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value
    if ($content -notmatch 'blue notebook' -or $content -notmatch 'design review') { throw "Unexpected synthetic transcript: $content" }
    Write-Output "The verified transcript appeared $([math]::Round(([DateTime]::UtcNow - $fileSelected).TotalSeconds,1)) seconds after the file picker returned."
    Write-Output "The Windows release transcribed the blue notebook and design review phrases in $([math]::Round(([DateTime]::UtcNow - $started).TotalSeconds,1)) seconds including file selection."
    Open-Control (Wait-Control 'Save to Library')
    $null = Wait-Control 'Saved on this device.'
    Open-Control (Wait-Control 'Library' 60 'Hyperlink')
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
