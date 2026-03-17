Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:VerbatimWindowsIdentityName = "AVA.Verbatim.Windows"
$script:WindowsShellTargetFramework = "net8.0-windows10.0.19041.0"

function Get-VerbatimRepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
}

function Get-WindowsShellProjectPath {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot)
    )

    return Join-Path $RepoRoot "Shells\windows\Verbatim.Windows\Verbatim.Windows.csproj"
}

function Get-WindowsShellPackageRoot {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot)
    )

    return Join-Path $RepoRoot "Shells\windows\Verbatim.Windows.Package"
}

function Assert-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$InstallHint
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found on PATH. $InstallHint"
    }
}

function Assert-VisualStudioInstalled {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "Visual Studio installer tooling was not found. Install Visual Studio with WinUI support before building the packaged Windows shell."
    }

    $instances = & $vswhere -latest -products * -format json | ConvertFrom-Json
    if (-not $instances) {
        throw "No Visual Studio installation with WinUI tooling was detected."
    }
}

function Assert-WindowsSdkInstalled {
    $includeRoot = "C:\Program Files (x86)\Windows Kits\10\Include"
    if (-not (Test-Path $includeRoot)) {
        throw "Windows SDK headers were not found under $includeRoot. Install Windows SDK 10.0.19041.0 or newer."
    }

    $versions = Get-ChildItem $includeRoot -Directory | Select-Object -ExpandProperty Name
    if (-not ($versions | Where-Object { [version]$_ -ge [version]"10.0.19041.0" })) {
        throw "Windows SDK 10.0.19041.0 or newer is required for the packaged Windows shell."
    }
}

function Assert-WinUiTemplateAvailable {
    $templates = & dotnet new list winui 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $templates -notmatch "WinUI 3 App") {
        throw "The WinUI template is not available from dotnet new. Install the WinUI workload before building the packaged Windows shell."
    }
}

function Assert-WindowsShellPrerequisites {
    Assert-CommandAvailable -Name "dotnet" -InstallHint "Install the .NET SDK and make sure dotnet.exe is available."
    Assert-CommandAvailable -Name "cargo" -InstallHint "Install Rust and make sure cargo.exe is available."
    Assert-VisualStudioInstalled
    Assert-WindowsSdkInstalled
    Assert-WinUiTemplateAvailable
}

function Get-WindowsRuntimeIdentifier {
    param(
        [ValidateSet("x64")]
        [string]$Platform = "x64"
    )

    return "win-$Platform"
}

function Get-WindowsShellOutputRoot {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug",
        [ValidateSet("x64")]
        [string]$Platform = "x64"
    )

    $rid = Get-WindowsRuntimeIdentifier -Platform $Platform
    return Join-Path $RepoRoot "Shells\windows\Verbatim.Windows\bin\$Platform\$Configuration\$script:WindowsShellTargetFramework\$rid"
}

function Get-WindowsShellBuildManifestPath {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug",
        [ValidateSet("x64")]
        [string]$Platform = "x64"
    )

    return Join-Path (Get-WindowsShellOutputRoot -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform) "AppxManifest.xml"
}

function Get-WindowsShellPackageOutputRoot {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug",
        [ValidateSet("x64")]
        [string]$Platform = "x64"
    )

    return Join-Path (Get-WindowsShellPackageRoot -RepoRoot $RepoRoot) "AppPackages\$Platform\$Configuration\"
}

function Get-WindowsShellPackageManifestPath {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug",
        [ValidateSet("x64")]
        [string]$Platform = "x64"
    )

    $packageRoot = Get-WindowsShellPackageOutputRoot -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    if (-not (Test-Path $packageRoot)) {
        return $null
    }

    return (Get-ChildItem $packageRoot -Recurse -Filter "AppxManifest.xml" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName)
}

function Get-WindowsShellPackagePath {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug",
        [ValidateSet("x64")]
        [string]$Platform = "x64"
    )

    $packageRoot = Get-WindowsShellPackageOutputRoot -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    if (-not (Test-Path $packageRoot)) {
        return $null
    }

    return (Get-ChildItem $packageRoot -Recurse -Include "*.msix", "*.appx" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName)
}

function Get-WindowsShellPackageInstallerPath {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug",
        [ValidateSet("x64")]
        [string]$Platform = "x64"
    )

    $packageRoot = Get-WindowsShellPackageOutputRoot -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    if (-not (Test-Path $packageRoot)) {
        return $null
    }

    return (Get-ChildItem $packageRoot -Recurse -Filter "Install.ps1" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName)
}

function Invoke-WindowsRustBuild {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug"
    )

    $rustCoreScript = Join-Path $RepoRoot "scripts\build_rust_core.ps1"
    if ($Configuration -eq "Release") {
        & $rustCoreScript -Release
    }
    else {
        & $rustCoreScript
    }
}

function Invoke-WindowsShellHostBuild {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug",
        [ValidateSet("x64")]
        [string]$Platform = "x64",
        [string[]]$ForwardedArgs = @()
    )

    Assert-WindowsShellPrerequisites
    Invoke-WindowsRustBuild -RepoRoot $RepoRoot -Configuration $Configuration

    $project = Get-WindowsShellProjectPath -RepoRoot $RepoRoot
    & dotnet build $project -c $Configuration -p:Platform=$Platform -m:1 @ForwardedArgs
}

function Publish-WindowsShellPackage {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug",
        [ValidateSet("x64")]
        [string]$Platform = "x64",
        [string[]]$ForwardedArgs = @()
    )

    Assert-WindowsShellPrerequisites
    Invoke-WindowsRustBuild -RepoRoot $RepoRoot -Configuration $Configuration

    $project = Get-WindowsShellProjectPath -RepoRoot $RepoRoot
    $packageRoot = Get-WindowsShellPackageOutputRoot -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    $rid = Get-WindowsRuntimeIdentifier -Platform $Platform

    New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

    $publishArgs = @(
        "publish",
        $project,
        "-c", $Configuration,
        "-p:Platform=$Platform",
        "-p:RuntimeIdentifier=$rid",
        "-p:GenerateAppxPackageOnBuild=true",
        "-p:AppxBundle=Never",
        "-p:UapAppxPackageBuildMode=SideloadOnly",
        "-p:AppxPackageSigningEnabled=false",
        "-p:GenerateAppInstallerFile=false",
        "-p:AppxPackageDir=$packageRoot",
        "-m:1"
    ) + $ForwardedArgs

    & dotnet @publishArgs

    $packagePath = Get-WindowsShellPackagePath -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    if ($packagePath) {
        return $packagePath
    }

    $packageManifest = Get-WindowsShellPackageManifestPath -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    if ($packageManifest) {
        return $packageManifest
    }

    $buildManifest = Get-WindowsShellBuildManifestPath -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    if (Test-Path $buildManifest) {
        return $buildManifest
    }

    throw "Package publish completed but no package artifact or manifest was found under $packageRoot."
}

function Invoke-WindowsShellBuild {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug",
        [ValidateSet("x64")]
        [string]$Platform = "x64",
        [string[]]$ForwardedArgs = @()
    )

    return Publish-WindowsShellPackage -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform -ForwardedArgs $ForwardedArgs
}

function Register-WindowsShellPackage {
    param(
        [string]$RepoRoot = (Get-VerbatimRepoRoot),
        [ValidateSet("Debug", "Release")]
        [string]$Configuration = "Debug",
        [ValidateSet("x64")]
        [string]$Platform = "x64"
    )

    $buildManifest = Get-WindowsShellBuildManifestPath -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    if (Test-Path $buildManifest) {
        Add-AppxPackage -ForceApplicationShutdown -Register $buildManifest
        return $buildManifest
    }

    $packageInstaller = Get-WindowsShellPackageInstallerPath -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    if ($packageInstaller) {
        try {
            & $packageInstaller -Force -SkipLoggingTelemetry
            return $packageInstaller
        }
        catch {
            Write-Warning "Package install script failed at $packageInstaller. Falling back to direct package registration. $($_.Exception.Message)"
        }
    }

    $packageManifest = Get-WindowsShellPackageManifestPath -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    if ($packageManifest) {
        Add-AppxPackage -ForceApplicationShutdown -Register $packageManifest
        return $packageManifest
    }

    $packagePath = Get-WindowsShellPackagePath -RepoRoot $RepoRoot -Configuration $Configuration -Platform $Platform
    if ($packagePath) {
        Add-AppxPackage -ForceApplicationShutdown -AllowUnsigned -Path $packagePath
        return $packagePath
    }

    throw "Packaged manifest was not found under the build output or package output roots. Build the Windows shell first."
}

function Get-WindowsShellAppId {
    $app = Get-StartApps |
        Where-Object { $_.AppID -like "$script:VerbatimWindowsIdentityName*!App" } |
        Select-Object -First 1

    if (-not $app) {
        throw "The packaged Verbatim app was not registered in Start Apps."
    }

    return $app.AppID
}

function Launch-WindowsShellPackage {
    $appId = Get-WindowsShellAppId
    Start-Process "shell:AppsFolder\$appId"
    return $appId
}

function Wait-WindowsShellWindow {
    param(
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $process = Get-Process | Where-Object { $_.MainWindowTitle -like "Verbatim*" } | Select-Object -First 1
        if ($process) {
            return $process
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    throw "The packaged Verbatim app did not expose a top-level Verbatim window within $TimeoutSeconds seconds."
}
