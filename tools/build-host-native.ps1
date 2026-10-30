$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$package=Join-Path $root 'packages\desktop-pet'
$source=Join-Path $package 'WhaleHostNative.cs'
$output=Join-Path $package 'whale-host-native.dll'
$temp=Join-Path $package ('whale-host-native.'+[Guid]::NewGuid().ToString('N')+'.dll')
try{
  Add-Type -TypeDefinition ([IO.File]::ReadAllText($source)) -OutputAssembly $temp -OutputType Library
  if([IO.File]::Exists($output)){[IO.File]::Replace($temp,$output,[NullString]::Value)}else{[IO.File]::Move($temp,$output)}
}finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
Write-Host 'Built whale-host-native.dll for Windows PowerShell 5.1.'
