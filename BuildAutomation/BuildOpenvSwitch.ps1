$ErrorActionPreference = "Stop"

<#
Install requirements first, see: Installrequirements.ps1
#>
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\BuildUtils.ps1"
. "$scriptPath\Dependencies.ps1"

# Make sure ActivePerl comes before MSYS Perl, otherwise
# the OpenSSL build will fail
$ENV:PATH = "C:\Perl\bin;$ENV:PATH"
$ENV:PATH += ";$ENV:ProgramFiles\7-Zip"
$ENV:PATH += ";${ENV:ProgramFiles(x86)}\Git\bin"
$ENV:PATH += ";${ENV:ProgramFiles(x86)}\CMake 2.8\bin"
$ENV:PATH += ";${ENV:ProgramFiles(x86)}\nasm"

$mingwBaseDir = "C:\MinGW"

$vsVersion = "12.0"

$cmakeGenerator = "Visual Studio $($vsVersion.Split(".")[0])"
$platformToolset = "v$($vsVersion.Replace('.', ''))"

SetVCVars $vsVersion

$pthreadsWin32Base = "pthreads-w32-2-9-1-release"
$pthreadsWin32MD5 = "a3cb284ba0914c9d26e0954f60341354"

$opensslVersion = "1.0.1h"
$opensslSha1 = "b2239599c8bf8f7fc48590a55205c26abe560bf8"

$basePath = "C:\OpenStack\build\OpenvSwitch"
$buildDir = "$basePath\Build"
$outputPath = "$buildDir\bin"

$ENV:OPENSSL_ROOT_DIR="$outputPath\OpenSSL"

# Needed for SSH
$ENV:HOME = $ENV:USERPROFILE

$sign_cert_thumbprint = "65c29b06eb665ce202676332e8129ac48d613c61"

CheckDir $basePath
pushd .
try
{
    CheckRemoveDir $buildDir
    mkdir $buildDir
    cd $buildDir
    mkdir $outputPath
    BuildOpenSSL $buildDir $outputPath $opensslVersion $cmakeGenerator $platformToolset $true $true $opensslSha1
    BuildPthreadsW32 $buildDir $outputPath $pthreadsWin32Base $pthreadsWin32MD5

    $openvSwitchHyperVDir = "openvswitch-hyperv"

    ExecRetry {
        # Make sure to have a private key that matches a github deployer key in $ENV:HOME\.ssh\id_rsa
        GitClonePull $openvSwitchHyperVDir "https://github.com/aserdean/openvswitch_bond_interfaces.git"
    }

    $thirdPartyBaseDir = "$openvSwitchHyperVDir\windows\thirdparty"
    $winPthreadLibDir = "$thirdPartyBaseDir\winpthread\lib\x86"

    CheckDir $winPthreadLibDir

    copy -Force "$buildDir\openssl-$opensslVersion\out32dll\libeay32.lib" $thirdPartyBaseDir
    copy -Force "$buildDir\openssl-$opensslVersion\out32dll\ssleay32.lib" $thirdPartyBaseDir
    copy -Force "$buildDir\$pthreadsWin32Base\pthreads.2\pthreadVC2.lib" $winPthreadLibDir

    $ENV:PATH = "$mingwBaseDir\msys\1.0\bin\;$ENV:PATH"

    pushd .
    try
    {
        cd $openvSwitchHyperVDir

        $msysCwd = "/" + $pwd.path.Replace("\", "/").Replace(":", "")
        $pthreadDir = ($buildDir + "\" + $winPthreadLibDir).Replace("\", "/")
        $vsLinkPath = $(Get-Command link.exe).path

        $msysScript = @"
#!/bin/bash
set -e
cd $msysCwd
./boot.sh
./configure CC=./build-aux/cccl LD="$vsLinkPath" LIBS="-lws2_32" --prefix="C:/ProgramData/openvswitch" \
--localstatedir="C:/ProgramData/openvswitch" --sysconfdir="C:/ProgramData/openvswitch" \
--with-pthread="$pthreadDir" --with-vstudioddk="Win8.1 Release"
make clean && make
exit
"@
        $msysScriptPath = Join-Path $pwd "build.sh"
        $msysScript.Replace("`r`n","`n") | Set-Content $msysScriptPath -Force
        &sh --login -i $msysScriptPath
        if ($LastExitCode) { throw "build.sh failed" }
        del $msysScriptPath

        copy -Force ".\ovsdb\*.exe" $outputPath
        copy -Force ".\vswitchd\*.exe" $outputPath
        copy -Force ".\vswitchd\vswitch.ovsschema" $outputPath
        copy -Force ".\utilities\*.exe" $outputPath
    }
    finally
    {
        popd
    }

    $driverOutputPath = "$outputPath\openvswitch_driver"
    mkdir $driverOutputPath

    $sysFileName = "ovsext.sys"
    $infFileName = "ovsext.inf"
    $catFileName = "ovsext.cat"

    pushd .
    try
    {
        cd "$openvSwitchHyperVDir\datapath-windows"

        copy -Force "x64\Win8.1Release\package\$sysFileName" $driverOutputPath
        copy -Force "x64\Win8.1Release\package\$infFileName" $driverOutputPath
        copy -Force "x64\Win8.1Release\package\$catFileName" $driverOutputPath
    }
    finally
    {
        popd
    }

    copy -Force "$openvSwitchHyperVDir\datapath-windows\misc\OVS.psm1" $outputPath

    # See: https://knowledge.verisign.com/support/code-signing-support/index?page=content&id=SO5820&act=RATE&viewlocale=en_US&newguid=015203267fad9a701464fd90342007e8d
    $crossCertPath = "$scriptPath\After_10-10-10_MSCV-VSClass3.cer"

    ExecRetry {
        &signtool.exe sign /ac "$crossCertPath" /sha1 $sign_cert_thumbprint /t http://timestamp.verisign.com/scripts/timstamp.dll /v "$driverOutputPath\$sysFileName"
        if ($LastExitCode) { throw "signtool failed" }
    }

    &inf2cat.exe /driver:$driverOutputPath /os:8_x64
    if ($LastExitCode) { throw "inf2cat failed" }

    ExecRetry {
        &signtool.exe sign /ac "$crossCertPath" /sha1 $sign_cert_thumbprint /t http://timestamp.verisign.com/scripts/timstamp.dll /v "$driverOutputPath\$catFileName"
        if ($LastExitCode) { throw "signtool failed" }
    }
}
finally
{
    popd
}
