param(
  [Parameter(Mandatory)][string]$InstalledDirectory,
  [Parameter(Mandatory)][string]$ProjectDirectory,
  [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9.-]{3,50}$')][string]$IdentityName,
  [Parameter(Mandatory)][string]$Publisher,
  [Parameter(Mandatory)][string]$PublisherDisplayName,
  [Parameter(Mandatory)][string]$OutputFile
)

$ErrorActionPreference = 'Stop'
$app = @(Get-ChildItem $InstalledDirectory -File -Filter '*.exe' |
  Where-Object { $_.BaseName -match '^Vyrra[- ]Desktop$' })
if ($app.Count -ne 1) { throw 'Expected the installed Vyrra Desktop executable.' }
$kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
$sdk = Get-ChildItem $kits -Directory |
  Where-Object { $_.Name -as [version] } |
  Sort-Object { [version]$_.Name } -Descending |
  Where-Object { Test-Path (Join-Path $_.FullName 'x64/makeappx.exe') } |
  Select-Object -First 1
if (-not $sdk) { throw 'The Windows SDK MakeAppx tool is required.' }
$makeappx = Join-Path $sdk.FullName 'x64/makeappx.exe'
$config = Get-Content (Join-Path $ProjectDirectory 'tauri.conf.json') -Raw | ConvertFrom-Json
$version = [version]$config.version
# Offset the major version so 0.x previews and later 1.x releases sort in order.
# The Store reserves the fourth number for its own updates.
$storeMajor = $version.Major + 1
$storeVersion = "$storeMajor.$($version.Minor).$($version.Build).0"
$layout = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()))
$unpacked = Join-Path $layout.FullName 'validation'
$payload = New-Item -ItemType Directory -Path (Join-Path $layout.FullName 'package')
try {
  Get-ChildItem $InstalledDirectory | Where-Object { $_.Name -ne 'uninstall.exe' } | Copy-Item -Destination $payload.FullName -Recurse
  $assets = New-Item -ItemType Directory -Path (Join-Path $payload.FullName 'Assets')
  foreach ($icon in 'StoreLogo.png', 'Square44x44Logo.png', 'Square150x150Logo.png') {
    Copy-Item (Join-Path $ProjectDirectory "icons/$icon") $assets.FullName
  }
  [xml]$manifest = @'
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  xmlns:win32dependencies="http://schemas.microsoft.com/appx/manifest/externaldependencies"
  IgnorableNamespaces="uap rescap win32dependencies">
  <Identity Name="" Publisher="" Version="" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>Vyrra Desktop</DisplayName>
    <PublisherDisplayName />
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources><Resource Language="en-us" /></Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.20348.0" />
    <win32dependencies:ExternalDependency Name="Microsoft.WebView2" Publisher="CN=Microsoft Windows, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" MinVersion="1.1.1.1" Optional="false" />
  </Dependencies>
  <Applications>
    <Application Id="VyrraDesktop" Executable="" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="Vyrra Desktop" Description="Private, on-device dictation and meeting notes"
        Square150x150Logo="Assets\Square150x150Logo.png" Square44x44Logo="Assets\Square44x44Logo.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
    <DeviceCapability Name="microphone" />
  </Capabilities>
</Package>
'@
  $manifest.Package.Identity.SetAttribute('Name', $IdentityName)
  $manifest.Package.Identity.SetAttribute('Publisher', $Publisher)
  $manifest.Package.Identity.SetAttribute('Version', $storeVersion)
  $manifest.Package.Properties.PublisherDisplayName = $PublisherDisplayName
  $manifest.Package.Applications.Application.SetAttribute('Executable', $app[0].Name)
  $manifest.Save((Join-Path $payload.FullName 'AppxManifest.xml'))
  & $makeappx pack /d $payload.FullName /p $OutputFile /h SHA256 /no
  if ($LASTEXITCODE) { throw 'MakeAppx could not validate and pack the application.' }
  & $makeappx unpack /p $OutputFile /d $unpacked /no
  if ($LASTEXITCODE) { throw 'MakeAppx could not unpack the finished package.' }
  $packagedHash = (Get-FileHash (Join-Path $unpacked $app[0].Name)).Hash
  if ($packagedHash -ne (Get-FileHash $app[0].FullName).Hash) { throw 'The packaged binary differs from the tested installation.' }
  Write-Output "Validated Microsoft Store package $storeVersion and its native executable."
} finally {
  Remove-Item $layout.FullName -Recurse -Force
}
