$ErrorActionPreference='Stop'
$package=Join-Path (Split-Path -Parent $PSScriptRoot) 'packages\desktop-pet'
$native=[regex]::Replace([IO.File]::ReadAllText((Join-Path $package 'WhaleHostNative.cs')),'(?m)^using[^\r\n]*;\r?\n','')
$code="using System.Runtime.InteropServices;`n"+[IO.File]::ReadAllText((Join-Path $package 'WhaleHostWatch.cs'))+"`n"+$native
$output=Join-Path $package 'whale-host-watch.exe'
$temp=Join-Path $package ('whale-host-watch.'+[Guid]::NewGuid().ToString('N')+'.exe')
try{
  Add-Type -TypeDefinition $code -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll') -OutputAssembly $temp -OutputType WindowsApplication
  if([IO.File]::Exists($output)){[IO.File]::Replace($temp,$output,[NullString]::Value)}else{[IO.File]::Move($temp,$output)}
}finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
Write-Host 'Built silent whale-host-watch.exe for .NET Framework.'
