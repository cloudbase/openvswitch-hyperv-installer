Param(
  [string]$OVSGitBranch = "branch-2.12-cloudbase",
  [string]$SignX509Thumbprint,
  [string]$SignTimestampUrl = "http://timestamp.globalsign.com/?signature=sha2",
  [string]$SignCrossCertPath = "$scriptPath\GlobalSign_r1cross.cer"
)

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
$ENV:PATH += ";C:\Python27"

# Try to use MSYS2 first. Ensure to have the following:
# pacman -S binutils make autoconf automake libtool
$msysBinDir = "C:\msys64\usr\bin"
if(!(Test-Path $msysBinDir))
{
    $msysBinDir = "C:\MinGW\msys\1.0\bin"
}

$vsVersion = "12.0"

$platform = "x86_amd64"

$cmakePlatformMap = @{"x86"=""; "amd64"=" Win64"; "x86_amd64"=" Win64"}
$cmakeGenerator = "Visual Studio $($vsVersion.Split(".")[0])$($cmakePlatformMap[$platform])"
$platformToolset = "v$($vsVersion.Replace('.', ''))"

SetVCVars $vsVersion $platform

$pthreadsWin32Base = "pthreads-w32-2-9-1-release"
$pthreadsWin32MD5 = "a3cb284ba0914c9d26e0954f60341354"

$opensslVersion = "1.0.2l"
$opensslSha1 = "b58d5d0e9cea20e571d903aafa853e2ccd914138"

$basePath = "C:\Build\OpenvSwitch_${OVSGitBranch}"
$buildDir = "$basePath\Build"
$outputPath = "$buildDir\bin"
$outputSymbolsPath = "$buildDir\symbols"

$ENV:OPENSSL_ROOT_DIR="$outputPath\OpenSSL"

# Needed for SSH
$ENV:HOME = $ENV:USERPROFILE

CheckDir $basePath
pushd .
try
{
    CheckRemoveDir $buildDir
    mkdir $buildDir
    CheckRemoveDir $outputSymbolsPath
    mkdir $outputSymbolsPath
    cd $buildDir
    mkdir $outputPath
    BuildOpenSSL $buildDir $outputPath $opensslVersion $platform $cmakeGenerator $platformToolset $true $true $opensslSha1
    BuildPthreadsW32 $buildDir $outputPath $pthreadsWin32Base $pthreadsWin32MD5

    $openvSwitchHyperVDir = "ovs"

    ExecRetry {
        # Make sure to have a private key that matches a github deployer key in $ENV:HOME\.ssh\id_rsa
        GitClonePull $openvSwitchHyperVDir "https://github.com/cloudbase/ovs.git" $OVSGitBranch
    }

    $thirdPartyBaseDir = "$openvSwitchHyperVDir\windows\thirdparty"

    $automakePlatformMap = @{"x86"="x86"; "amd64"="x64"; "x86_amd64"="x64"}
    $winPthreadLibDir = "$thirdPartyBaseDir\winpthread\lib\$($automakePlatformMap[$platform])"

    CheckDir $winPthreadLibDir
    copy -Force "$buildDir\openssl-$opensslVersion\out32dll\libeay32.lib" $thirdPartyBaseDir
    copy -Force "$buildDir\openssl-$opensslVersion\out32dll\ssleay32.lib" $thirdPartyBaseDir
    mv "$buildDir\openssl-$opensslVersion\include" "$buildDir\openssl-$opensslVersion\include_linux"
    mv "$buildDir\openssl-$opensslVersion\inc32" "$buildDir\openssl-$opensslVersion\include"
    copy -Force "$buildDir\$pthreadsWin32Base\pthreads.2\pthreadVC2.lib" $winPthreadLibDir
    mv "$buildDir\openssl-$opensslVersion\out32dll" "$buildDir\openssl-$opensslVersion\lib"

    #automake already appends \lib\<platform> to the pthread library
    $winPthreadLibDir = "$thirdPartyBaseDir\winpthread"

    pushd .
    try
    {
        cd $openvSwitchHyperVDir

        $msysCwd = "/" + $pwd.path.Replace("\", "/").Replace(":", "")
        $pthreadDir = ($buildDir + "\" + $winPthreadLibDir).Replace("\", "/")
        $opensslDir = ($buildDir + "\openssl-$opensslVersion\").Replace("\", "/")
        # This must be the Visual Studio version of link.exe, not MinGW
        $vsLinkPath = $(Get-Command link.exe).path

        $msysScript = @"
#!/bin/bash
set -e
cd $msysCwd
echo `$INCLUDE
./boot.sh
./configure CC=./build-aux/cccl LD="$vsLinkPath" LIBS="-lws2_32 -lShlwapi -liphlpapi -lwbemuuid -lole32 -loleaut32" --prefix="C:/ProgramData/openvswitch" \
--localstatedir="C:/ProgramData/openvswitch" --sysconfdir="C:/ProgramData/openvswitch" \
--with-pthread="$pthreadDir" --with-vstudiotarget="Release" --enable-ssl --with-openssl="$opensslDir"
make clean && make
exit
"@

        echo $msysScript
        $msysScriptPath = Join-Path $pwd "build.sh"
        $msysScript.Replace("`r`n","`n") | Set-Content $msysScriptPath -Force

        $ENV:PATH = "$msysBinDir;$ENV:PATH"
        &bash.exe $msysScriptPath
        if ($LastExitCode) { throw "build.sh failed" }

        del $msysScriptPath

        copy -Force ".\ovsdb\*.exe" $outputPath
        copy -Force ".\vswitchd\*.exe" $outputPath
        copy -Force ".\vswitchd\vswitch.ovsschema" $outputPath
        copy -Force ".\utilities\*.exe" $outputPath
        copy -Force ".\ovn\ovn-nb.ovsschema" $outputPath
        copy -Force ".\ovn\ovn-sb.ovsschema" $outputPath
        copy -Force ".\ovn\controller\*.exe" $outputPath
        copy -Force ".\ovn\northd\*.exe" $outputPath
        copy -Force ".\ovn\utilities\*.exe" $outputPath

        copy -Force ".\ovsdb\*.pdb" $outputSymbolsPath
        copy -Force ".\vswitchd\*.pdb" $outputSymbolsPath
        copy -Force ".\utilities\*.pdb" $outputSymbolsPath
        copy -Force ".\ovn\controller\*.pdb" $outputSymbolsPath
        copy -Force ".\ovn\northd\*.pdb" $outputSymbolsPath
        copy -Force ".\ovn\utilities\*.pdb" $outputSymbolsPath
    }
    finally
    {
        popd
    }

    #We will copy both Win8/8.1 release since the installer will automatically
    #choose which version should be installed
    $driverOutputPath_2012_r2 = "$outputPath\openvswitch_driver\Win8.1"
    mkdir $driverOutputPath_2012_r2

    $driverOutputPath_2012 = "$outputPath\openvswitch_driver\Win8"
    mkdir $driverOutputPath_2012

    $sysFileName = "ovsext.sys"
    $infFileName = "ovsext.inf"
    $catFileName = "ovsext.cat"
    $pdbDriverFileName = "OVSExt.pdb"

    pushd .
    try
    {
        cd "$openvSwitchHyperVDir\datapath-windows"

        copy -Force "x64\Win8.1Release\package\$sysFileName" $driverOutputPath_2012_r2
        copy -Force "x64\Win8.1Release\package\$infFileName" $driverOutputPath_2012_r2
        copy -Force "x64\Win8.1Release\package\$catFileName" $driverOutputPath_2012_r2
        copy -Force "ovsext\x64\Win8.1Release\$pdbDriverFileName" $driverOutputPath_2012_r2
        copy -Force "x64\Win8Release\package\$sysFileName" $driverOutputPath_2012
        copy -Force "x64\Win8Release\package\$infFileName" $driverOutputPath_2012
        copy -Force "x64\Win8Release\package\$catFileName" $driverOutputPath_2012
        copy -Force "ovsext\x64\Win8Release\$pdbDriverFileName" $driverOutputPath_2012
    }
    finally
    {
        popd
    }

    copy -Force "$openvSwitchHyperVDir\datapath-windows\misc\OVS.psm1" $outputPath
    copy -Force "$openvSwitchHyperVDir\datapath-windows\misc\HNSHelper.psm1" $outputPath

    # For signing info, see:
    # https://knowledge.symantec.com/support/code-signing-support/index?page=content&id=SO5820
    # https://support.globalsign.com/customer/portal/articles/1698751-ev-code-signing-for-windows-7-and-8

    if($SignX509Thumbprint)
    {
        ExecRetry {
            Write-Host "Signing 2012 R2 driver with certificate: $SignX509Thumbprint"
            SignTool $SignCrossCertPath $SignX509Thumbprint $SignTimestampUrl "$driverOutputPath_2012_r2\$sysFileName"
        }
        ExecRetry {
            Write-Host "Signing 2012 driver with certificate: $SignX509Thumbprint"
            SignTool $SignCrossCertPath $SignX509Thumbprint $SignTimestampUrl "$driverOutputPath_2012\$sysFileName"
        }
    }
    else
    {
        Write-Warning "Driver not signed since the X509 thumbprint has not been specified!"
    }

    &inf2cat.exe /driver:$driverOutputPath_2012_r2 /os:Server6_3_X64 /uselocaltime
    if ($LastExitCode) { throw "inf2cat failed" }
    &inf2cat.exe /driver:$driverOutputPath_2012 /os:Server8_X64 /uselocaltime
    if ($LastExitCode) { throw "inf2cat failed" }

    if($SignX509Thumbprint)
    {
        ExecRetry {
            Write-Host "Signing 2012 R2 CAT file with certificate: $SignX509Thumbprint"
            SignTool $SignCrossCertPath $SignX509Thumbprint $SignTimestampUrl "$driverOutputPath_2012_r2\$catFileName"
        }
        ExecRetry {
            Write-Host "Signing 2012 CAT file with certificate: $SignX509Thumbprint"
            SignTool $SignCrossCertPath $SignX509Thumbprint $SignTimestampUrl "$driverOutputPath_2012\$catFileName"
            if ($LastExitCode) { throw "signtool failed" }
        }
    }
}
finally
{
    popd
}
