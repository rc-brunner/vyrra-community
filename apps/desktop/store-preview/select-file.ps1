param([Parameter(Mandatory)][string]$AudioFile)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [Windows.Automation.AutomationElement]::RootElement
$dialogName = [Windows.Automation.PropertyCondition]::new(
  [Windows.Automation.AutomationElement]::NameProperty, 'Transcribe audio on this device')
$type = [Windows.Automation.PropertyCondition]::new(
  [Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Window)
$windowCondition = [Windows.Automation.AndCondition]::new($dialogName, $type)
$deadline = [DateTime]::UtcNow.AddSeconds(30)
do {
  $dialog = $root.FindFirst([Windows.Automation.TreeScope]::Descendants, $windowCondition)
  if ($null -ne $dialog) { break }
  Start-Sleep -Milliseconds 300
} while ([DateTime]::UtcNow -lt $deadline)
if ($null -eq $dialog) { throw 'The Vyrra WAV file picker did not open.' }
$scope = [Windows.Automation.TreeScope]::Descendants
$fileName = [Windows.Automation.PropertyCondition]::new(
  [Windows.Automation.AutomationElement]::AutomationIdProperty, '1148')
$editType = [Windows.Automation.PropertyCondition]::new(
  [Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit)
$deadline = [DateTime]::UtcNow.AddSeconds(5)
do {
  $field = $dialog.FindFirst($scope, $fileName)
  if ($null -ne $field -and $field.Current.ControlType -ne [Windows.Automation.ControlType]::Edit) {
    $field = $field.FindFirst($scope, $editType)
  }
  if ($null -eq $field) {
    $field = $dialog.FindAll($scope, $editType) | Where-Object { $_.Current.Name -match '^File name' } | Select-Object -First 1
  }
  if ($null -ne $field) { break }
  Start-Sleep -Milliseconds 250
} while ([DateTime]::UtcNow -lt $deadline)
$path = (Resolve-Path $AudioFile).Path
if ($null -eq $field) {
  $shell = New-Object -ComObject WScript.Shell
  if (-not $shell.AppActivate('Transcribe audio on this device')) { throw 'Could not focus the Vyrra WAV picker.' }
  $shell.SendKeys('%n')
  Start-Sleep -Milliseconds 300
  $focus = [Windows.Automation.AutomationElement]::FocusedElement
  if ($focus.Current.ProcessId -ne $dialog.Current.ProcessId) { throw 'Focus left the Vyrra WAV picker.' }
  $shell.SendKeys('^a')
  $shell.SendKeys($path)
  $shell.SendKeys('{ENTER}')
  return
}
$field.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($path)
$openId = [Windows.Automation.PropertyCondition]::new(
  [Windows.Automation.AutomationElement]::AutomationIdProperty, '1')
$open = $dialog.FindFirst($scope, $openId)
if ($null -eq $open) { throw 'Open button is missing from the Vyrra picker.' }
$open.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
