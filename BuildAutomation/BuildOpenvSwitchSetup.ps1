Param(
  [string]$Branch = "2.7",
  [string]$OVSGitBranch = "branch-2.7-cloudbase",
  [string]$SignX509Thumbprint,
  [string]$SignTimestampUrl = "http://timestamp.globalsign.com/?signature=sha2",
  [string]$SignCrossCertPath = "$scriptPath\GlobalSign_r1cross.cer",
  [string]$OvsVersion = "2.7.0"
)

$ErrorActionPreference = "Stop"

<#
Install requirements first, see: Installrequirements.ps1
#>

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\BuildUtils.ps1"

$basePath = "C:\Build\OpenvSwitch_${OVSGitBranch}"

CheckDir $basePath
pushd .
try
{
    cd $basePath

    $ENV:PATH += ";$ENV:ProgramFiles (x86)\Git\bin\"
    # Needed for SSH
    $ENV:HOME = $ENV:USERPROFILE
    $ENV:PATH += ";$ENV:ProgramFiles\7-zip\"

    $vsVersion = "12.0"
    $platform = "x86_amd64"
    SetVCVars $vsVersion $platform

    $solution_dir = Join-Path $pwd "openvswitch-hyperv-installer"

    ExecRetry {
        # Make sure to have a private key that matches a github deployer key in $ENV:HOME\.ssh\id_rsa
        GitClonePull $solution_dir "git@github.com:/cloudbase/openvswitch-hyperv-installer.git" $Branch
    }

    $msi_project_dir = "$solution_dir\openvswitch-hyperv-installer"

    $buildDir = "$basePath\Build"
    $buildOutputDir = "$buildDir\bin"
    $buildOutputSymbolsDir = "$buildDir\symbols"
    $driverBuildOutputDir = "$buildOutputDir\openvswitch_driver"

    $ovsCliBinDir = "$msi_project_dir\Binaries"
    $ovsServicesBinDir = "$msi_project_dir\Services"
    $ovsDriverBinDir = "$msi_project_dir\Driver"
    $ovsSymbolsZipPath = "$buildDir\Symbols.zip"

    CheckRemoveDir $ovsCliBinDir
    mkdir $ovsCliBinDir
    copy "$buildOutputDir\*.dll" $ovsCliBinDir
    copy "$buildOutputDir\*.exe" $ovsCliBinDir

    CheckRemoveDir $ovsServicesBinDir
    mkdir $ovsServicesBinDir
    move -Force "$ovsCliBinDir\ovsdb-server.exe" $ovsServicesBinDir
    move -Force "$ovsCliBinDir\ovs-vswitchd.exe" $ovsServicesBinDir
    move -Force "$ovsCliBinDir\ovn-controller.exe" $ovsServicesBinDir
    move -Force "$ovsCliBinDir\ovn-northd.exe" $ovsServicesBinDir
    copy -Force "$buildOutputDir\vswitch.ovsschema" $ovsServicesBinDir
    copy -Force "$buildOutputDir\ovn-nb.ovsschema" $ovsServicesBinDir
    copy -Force "$buildOutputDir\ovn-sb.ovsschema" $ovsServicesBinDir
    copy -Force "$buildOutputDir\OVS.psm1" $msi_project_dir

    CheckRemoveDir $ovsDriverBinDir
    mkdir $ovsDriverBinDir
    copy -Recurse -Force "$driverBuildOutputDir\*" $ovsDriverBinDir

    pushd $buildOutputSymbolsDir
    try
    {
        if (Test-Path $ovsSymbolsZipPath) {
            del $ovsSymbolsZipPath
        }
        CreateZip $ovsSymbolsZipPath *
    }
    finally
    {
        popd
    }

    pushd .
    try
    {
        cd $solution_dir
        &msbuild openvswitch-hyperv-installer.sln /p:Platform=x64 /p:Configuration=Release /property:Version="$OvsVersion"
        if ($LastExitCode) { throw "MSBuild failed" }
    }
    finally
    {
        popd
    }

    $msi_path = "$msi_project_dir\bin\x64\Release\en-us\OpenvSwitch.msi"

    if($SignX509Thumbprint)
    {
        ExecRetry {
            Write-Host "Signing MSI with certificate: $SignX509Thumbprint"
            SignTool $SignCrossCertPath $SignX509Thumbprint $SignTimestampUrl $msi_path
        }
    }
    else
    {
        Write-Warning "MSI not signed"
    }
}
finally
{
    popd
}
