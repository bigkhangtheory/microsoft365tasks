[cmdletBinding()]
Param (
    [Parameter(Position = 0)]
    $Tasks,

    [switch]
    $ResolveDependency,

    [string]
    $BuildOutput = 'BuildOutput',

    [string]
    $Repository = 'PSGallery',

    [uri]
    $RepositoryProxy
)

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
$buildModulesPath = Join-Path -Path $BuildOutput -ChildPath Modules
$projectPath = $PSScriptRoot
$timeStamp = Get-Date -UFormat '%Y%m%d-%H%M%S'
$psVersion = $PSVersionTable.PSVersion.Major
$lines = '----------------------------------------------------------------------'

#changing the path is required to make PSDepend run without internet connection. It is required to download nutget.exe once first:
#Invoke-WebRequest -Uri 'https://aka.ms/psget-nugetexe' -OutFile C:\ProgramData\Microsoft\Windows\PowerShell\PowerShellGet\nuget.exe -ErrorAction Stop
$pathElements = $env:Path -split ';'
$pathElements += 'C:\ProgramData\Microsoft\Windows\PowerShell\PowerShellGet'
$env:Path = $pathElements -join ';'

if (-not (Get-Module -Name PackageManagement)) {
    Import-Module -Name PackageManagement #import it before the PSModulePath is changed prevents PowerShell from loading it
}

if (-not (Test-Path -Path $buildModulesPath)) {
    $null = mkdir -Path $buildModulesPath -Force
}

if ($buildModulesPath -notin ($Env:PSModulePath -split ';')) {
    $env:PSModulePath = "$buildModulesPath;$Env:PSModulePath"
}

if (-not (Get-Module -Name InvokeBuild -ListAvailable) -and -not $ResolveDependency) {
    Write-Error "Requirements are missing. Please call the script again with the switch 'ResolveDependency'"
    return
}

#importing all resources from .build directory
Get-ChildItem -Path "$PSScriptRoot/Build" -Recurse -Include *.ps1 |
ForEach-Object {
    Write-Verbose "Importing file $($_.BaseName)"
    try {
        . $_.FullName
    } catch { }
}

#register MAP powershell repository and set the repository
if ($env:NugetFeed) {
    if ($null -eq (Get-PSRepository -Name $env:NugetFeed)) {
        $Splatting = @{
            Name               = $env:NugetFeed
            SourceLocation     = $env:NugetApiUrl
            PublishLocation    = $env:NugetApiUrl
            InstallationPolicy = 'Trusted'
            Verbose            = $true
        }
        Register-PSRepository @Splatting
    }
}

if ($ResolveDependency) {
    . $PSScriptRoot/Build/BuildHelpers/Resolve-Dependency.ps1
    Resolve-Dependency
}

if ($MyInvocation.ScriptName -notlike '*Invoke-Build.ps1') {
    if ($ResolveDependency -or $PSBoundParameters['ResolveDependency']) {
        $PSBoundParameters.Remove('ResolveDependency')
    }

    if ($Help) {
        Invoke-Build ?
    } else {
        $PSBoundParameters.Remove('Tasks') | Out-Null
        Invoke-Build -Tasks $Tasks -File $MyInvocation.MyCommand.Path @PSBoundParameters
    }

    return
}

if (-not $Tasks) {
    task . Init,
    CleanBuildOutput,
    SetPsModulePath,
    CopyModule,
    IntegrationTest,
    Deploy,
    TestReleaseAcceptance
 
} else {
    task . $Tasks
}

Write-Host 'Running the folling tasks:' -ForegroundColor Magenta
${*}.All[-1].Jobs | ForEach-Object { "`t$_" } | Write-Host
Write-Host
