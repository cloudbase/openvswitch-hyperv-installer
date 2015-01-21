$ErrorActionPreference = "Stop"

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\BuildUtils.ps1"

iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))

ChocolateyInstall git.install

# Following packages either are not available / updated in Chocolatey or their Chocolatey packages have issues
DownloadInstall 'http://downloads.sourceforge.net/sevenzip/7z922-x64.msi' "msi"
DownloadInstall 'http://www.cmake.org/files/v2.8/cmake-2.8.12.2-win32-x86.exe' "exe" "/S"
DownloadInstall 'http://downloads.activestate.com/ActivePerl/releases/5.18.2.1802/ActivePerl-5.18.2.1802-MSWin32-x86-64int-298023.msi' "msi"
DownloadInstall 'http://download.microsoft.com/download/7/2/E/72E0F986-D247-4289-B9DC-C4FB07374894/wdexpress_full.exe' "exe" "/S /Q /Full"
DownloadInstall 'http://download.microsoft.com/download/8/2/6/826E264A-729E-414A-9E67-729923083310/VSU1/VS2013.1.exe' "exe" "/S /Q /Full"
# WDK 8.1 Update 1
DownloadInstall 'http://download.microsoft.com/download/0/8/C/08C7497F-8551-4054-97DE-60C0E510D97A/wdk/wdksetup.exe' "exe" "/features + /q"
# Note: nasm installs in a user location when executed withoud admin rights
DownloadInstall "http://www.nasm.us/pub/nasm/releasebuilds/2.11.02/win32/nasm-2.11.02-installer.exe" "exe" "/S"

# Install WiX after Visual Studio for integration
ChocolateyInstall wixtoolset

$ENV:PATH += ";${ENV:ProgramFiles(x86)}\Git\bin"

&git config --global user.name "Automated Build"
if ($LastExitCode) { throw "git config failed" }
&git config --global user.email "build@cloudbase"
if ($LastExitCode) { throw "git config failed" }

$toolsdir = "C:\Tools"
CheckDir $toolsdir

# TODO: Release AlexFTP 1.1.1 and replace the following beta
$path = "$ENV:TEMP\AlexFTPSBeta.zip" 
DownloadFile "https://www.cloudbase.it/downloads/AlexFTPSBeta.zip" $path
$ENV:PATH += ";$ENV:ProgramFiles\7-Zip"
Expand7z $path $toolsdir
del $path
Move "$toolsdir\Release" "$toolsdir\AlexFTPS-1.1.0"

$pfxPassword = "changeme"
$thumbprint = ImportCertificateUser "$ENV:USERPROFILE\Cloudbase_authenticode.p12" $pfxPassword
# TODO: write thumbrint to file and load it in the build script(s) in place of the hardcoded value
