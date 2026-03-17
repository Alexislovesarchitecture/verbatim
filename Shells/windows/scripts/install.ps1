param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArgs
)

. (Join-Path $PSScriptRoot "common.ps1")

$artifact = Invoke-WindowsShellBuild -Configuration "Debug" -Platform "x64" -ForwardedArgs $ForwardedArgs
$registration = Register-WindowsShellPackage -Configuration "Debug" -Platform "x64"

Write-Host "Prepared packaged Windows shell from $artifact"
Write-Host "Registered packaged Verbatim app using $registration"
