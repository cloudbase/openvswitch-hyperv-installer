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

$vsVersion = "12.0"

$cmakeGenerator = "Visual Studio $($vsVersion.Split(".")[0])"
SetVCVars $vsVersion

$pthreadsWin32Base = "pthreads-w32-2-9-1-release"
$opensslVersion = "1.0.1g"

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

    BuildOpenSSL $buildDir $outputPath $opensslVersion $cmakeGenerator $true
    BuildPthreadsW32 $buildDir $outputPath $pthreadsWin32Base


	$openvSwitchHyperVDir = "openvswitch-hyperv"

    ExecRetry {
        # Make sure to have a private key that matches a github deployer key in $ENV:HOME\.ssh\id_rsa
        GitClonePull $openvSwitchHyperVDir "git@github.com:/cloudbase/openvswitch-hyperv.git"
    }

	$thirdPartyBaseDir = "$openvSwitchHyperVDir\windows\thirdparty"
	$winPthreadLibDir = "$thirdPartyBaseDir\win-pthread\lib\x86"

	CheckDir $winPthreadLibDir

	copy -Force "$buildDir\openssl-$opensslVersion\out32dll\libeay32.lib" $thirdPartyBaseDir
	copy -Force "$buildDir\openssl-$opensslVersion\out32dll\ssleay32.lib" $thirdPartyBaseDir
	copy -Force "$buildDir\$pthreadsWin32Base\pthreads.2\pthreadVC2.lib" $winPthreadLibDir

	pushd .
	try
	{
		cd $openvSwitchHyperVDir

        &cmake . -G $cmakeGenerator
        if ($LastExitCode) { throw "cmake failed" }

        &msbuild OVS_Port.sln /p:Configuration=Release
        if ($LastExitCode) { throw "MSBuild failed" }

		copy -Force ".\ovsdb\Release\*.exe" $outputPath
		copy -Force ".\vswitchd\Release\*.exe" $outputPath
		copy -Force ".\vswitchd\vswitch.ovsschema" $outputPath
		copy -Force ".\utilities\Release\*.exe" $outputPath
	}
	finally
	{
		popd
	}

	$openvSwitchHyperVKernelDir = "openvswitch-hyperv-kernel"

    ExecRetry {
       GitClonePull $openvSwitchHyperVKernelDir "git@github.com:/cloudbase/openvswitch-hyperv-kernel.git"
    }

	$openvSwitchHyperVKernelDriverDir = "$openvSwitchHyperVKernelDir\openvswitch"

	$driverOutputPath = "$outputPath\openvswitch_driver"
	mkdir $driverOutputPath

	$sysFileName = "openvswitch.sys"
	$infFileName = "openvswitch.inf"
	$catFileName = "openvswitch.cat"

	pushd .
	try
	{
		cd $openvSwitchHyperVKernelDriverDir

        &msbuild  openvswitch.sln /p:Configuration="Win8.1 Release"
        if ($LastExitCode) { throw "MSBuild failed" }

		copy -Force ".\driver\x64\Win8.1Release\$sysFileName" $driverOutputPath
		copy -Force ".\driver\x64\Win8.1Release\$infFileName" $driverOutputPath
	}
	finally
	{
		popd
	}

	copy -Force "$openvSwitchHyperVKernelDir\Scripts\OVS.psm1" $outputPath

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
