param([Parameter(Mandatory)][string]$AudioFile)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [Windows.Automation.AutomationElement]::RootElement
$dialogName = [Windows.Automation.PropertyCondition]::new(
  [Windows.Automation.AutomationElement]::NameProperty, 'Transcribe audio on this device')
$deadline = [DateTime]::UtcNow.AddSeconds(30)
do {
  $dialog = $root.FindFirst([Windows.Automation.TreeScope]::Descendants, $dialogName)
  if ($null -ne $dialog) { break }
  Start-Sleep -Milliseconds 300
} while ([DateTime]::UtcNow -lt $deadline)
if ($null -eq $dialog) { throw 'The Vyrra WAV file picker did not open.' }
$scope = [Windows.Automation.TreeScope]::Descendants
$fileName = [Windows.Automation.PropertyCondition]::new(
  [Windows.Automation.AutomationElement]::AutomationIdProperty, '1148')
$editType = [Windows.Automation.PropertyCondition]::new(
  [Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit)
$field = $dialog.FindFirst($scope, $fileName)
if ($null -ne $field -and $field.Current.ControlType -ne [Windows.Automation.ControlType]::Edit) {
  $field = $field.FindFirst($scope, $editType)
}
if ($null -eq $field) {
  $field = $dialog.FindAll($scope, $editType) | Where-Object { $_.Current.Name -match '^File name' } | Select-Object -First 1
}
if ($null -eq $field) { throw 'File name control is missing from the Vyrra picker.' }
$field.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue((Resolve-Path $AudioFile).Path)
$openId = [Windows.Automation.PropertyCondition]::new(
  [Windows.Automation.AutomationElement]::AutomationIdProperty, '1')
$open = $dialog.FindFirst($scope, $openId)
if ($null -eq $open) { throw 'Open button is missing from the Vyrra picker.' }
$open.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
