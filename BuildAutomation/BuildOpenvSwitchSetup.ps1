$ErrorActionPreference = "Stop"

<#
Install requirements first, see: Installrequirements.ps1
#>

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\BuildUtils.ps1"

$basePath = "C:\OpenStack\build\OpenvSwitch"

CheckDir $basePath
pushd .
try
{
    cd $basePath

    $ENV:PATH += ";$ENV:ProgramFiles (x86)\Git\bin\"
    $ENV:PATH += ";C:\Tools\AlexFTPS-1.1.0"

    # Needed for SSH
    $ENV:HOME = $ENV:USERPROFILE

    $sign_cert_thumbprint = "65c29b06eb665ce202676332e8129ac48d613c61"
    $ftpsCredentials = GetCredentialsFromFile "$ENV:UserProfile\ftps.txt"

    SetVCVars

    $solution_dir = "openvswitch-hyperv-installer"

    ExecRetry {
        # Make sure to have a private key that matches a github deployer key in $ENV:HOME\.ssh\id_rsa
        GitClonePull $solution_dir "git@github.com:/cloudbase/openvswitch-hyperv-installer.git"
    }

    $msi_project_dir = "$solution_dir\openvswitch-hyperv-installer"

    $buildDir = "$basePath\Build"
    $buildOutputDir = "$buildDir\bin"
    $buildOutputSymbolsDir = "$buildDir\symbols"
    $driverBuildOutputDir = "$buildOutputDir\openvswitch_driver"

    $ovsCliBinDir = "$msi_project_dir\Binaries"
    $ovsServicesBinDir = "$msi_project_dir\Services"
    $ovsDriverBinDir = "$msi_project_dir\Driver"
    $ovsSymbolsDir = "$msi_project_dir\Symbols"

    CheckRemoveDir $ovsCliBinDir
    mkdir $ovsCliBinDir
    copy "$buildOutputDir\*.dll" $ovsCliBinDir
    copy "$buildOutputDir\*.exe" $ovsCliBinDir

    move -Force "$ovsCliBinDir\ovsdb-server.exe" $ovsServicesBinDir
    move -Force "$ovsCliBinDir\ovs-vswitchd.exe" $ovsServicesBinDir
    copy -Force "$buildOutputDir\vswitch.ovsschema" $ovsServicesBinDir	
    copy -Force "$buildOutputDir\OVS.psm1" $msi_project_dir

    CheckRemoveDir $ovsDriverBinDir
    mkdir $ovsDriverBinDir
    copy -Force "$driverBuildOutputDir\*" $ovsDriverBinDir

    CheckRemoveDir $ovsSymbolsDir
    mkdir $ovsSymbolsDir
    copy -Force "$buildOutputSymbolsDir\*" $ovsSymbolsDir

    pushd .
    try
    {
        cd $solution_dir
        &msbuild openvswitch-hyperv-installer.sln /p:Platform=x86 /p:Configuration=Release
        if ($LastExitCode) { throw "MSBuild failed" }
    }
    finally
    {
        popd
    }

    $msi_path = "$msi_project_dir\bin\Release\openvswitch-hyperv-installer.msi"

    ExecRetry {
        &signtool.exe sign /sha1 $sign_cert_thumbprint /t http://timestamp.verisign.com/scripts/timstamp.dll /v $msi_path
        if ($LastExitCode) { throw "signtool failed" }
    }

    $ftpsUsername = $ftpsCredentials.UserName
    $ftpsPassword = $ftpsCredentials.GetNetworkCredential().Password

    ExecRetry {
        &ftps -h www.cloudbase.it -ssl All -U $ftpsUsername -P $ftpsPassword -sslInvalidServerCertHandling Accept -p $msi_path /cloudbase.it/main/downloads/openvswitch-hyperv-installer-beta.msi
        if ($LastExitCode) { throw "ftps failed" }
    }
}
finally
{
    popd
}
