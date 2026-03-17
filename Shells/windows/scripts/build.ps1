param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArgs
)

. (Join-Path $PSScriptRoot "common.ps1")
$artifact = Invoke-WindowsShellBuild -Configuration "Debug" -Platform "x64" -ForwardedArgs $ForwardedArgs

Write-Host "Packaged Windows shell artifacts are ready."
Write-Host "Primary artifact: $artifact"
