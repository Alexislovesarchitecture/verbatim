param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArgs
)

. (Join-Path $PSScriptRoot "common.ps1")

Assert-WindowsShellPrerequisites

$repoRoot = Get-VerbatimRepoRoot
& cargo test --manifest-path (Join-Path $repoRoot "RustCore\Cargo.toml")
Invoke-WindowsShellHostBuild -RepoRoot $repoRoot -Configuration "Debug" -Platform "x64" -ForwardedArgs $ForwardedArgs | Out-Null
$artifact = Publish-WindowsShellPackage -RepoRoot $repoRoot -Configuration "Debug" -Platform "x64" -ForwardedArgs $ForwardedArgs

Write-Host "Verified Windows host build and package publish."
Write-Host "Primary artifact: $artifact"
