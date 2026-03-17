param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArgs
)

. (Join-Path $PSScriptRoot "common.ps1")

$artifact = Invoke-WindowsShellBuild -Configuration "Debug" -Platform "x64" -ForwardedArgs $ForwardedArgs
$registration = Register-WindowsShellPackage -Configuration "Debug" -Platform "x64"
$appId = Launch-WindowsShellPackage
$window = Wait-WindowsShellWindow

Write-Host "Launched packaged Verbatim app."
Write-Host "Build artifact: $artifact"
Write-Host "Registration target: $registration"
Write-Host "AppId: $appId"
Write-Host "Window title: $($window.MainWindowTitle)"
