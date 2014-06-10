$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\BuildUtils.ps1"


function BuildOpenSSL($buildDir, $outputPath, $opensslVersion, $cmakeGenerator, $platformToolset,
                      $dllBuild=$true, $runTests=$true, $hash=$null)
{
    $opensslBase = "openssl-$opensslVersion"
    $opensslPath = "$ENV:Temp\$opensslBase.tar.gz"
    $opensslUrl = "http://www.openssl.org/source/$opensslBase.tar.gz"

    pushd .
    try
    {
        cd $buildDir

        ExecRetry { (new-object System.Net.WebClient).DownloadFile($opensslUrl, $opensslPath) }

        if($hash) { ChechFileHash $opensslPath $hash }

        Expand7z $opensslPath
        del $opensslPath
        Expand7z "$opensslBase.tar"
        del "$opensslBase.tar"

        cd $opensslBase
        &cmake . -G $cmakeGenerator -T $platformToolset

        &perl Configure VC-WIN32 --prefix="$ENV:OPENSSL_ROOT_DIR"
        if ($LastExitCode) { throw "perl failed" }

        &.\ms\do_nasm
        if ($LastExitCode) { throw "do_nasm failed" }

        if($dllBuild)
        {
            $makFile = "ms\ntdll.mak"
        }
        else
        {
            $makFile = "ms\nt.mak"
        }

        &nmake -f $makFile
        if ($LastExitCode) { throw "nmake failed" }

        if($runTests)
        {
            &nmake -f $makFile test
            if ($LastExitCode) { throw "nmake test failed" }
        }

        &nmake -f $makFile install
        if ($LastExitCode) { throw "nmake install failed" }

        copy "$ENV:OPENSSL_ROOT_DIR\bin\*.dll" $outputPath
        copy "$ENV:OPENSSL_ROOT_DIR\bin\*.exe" $outputPath
    }
    finally
    {
        popd
    }
}

function BuildPthreadsW32($buildDir, $outputPath, $pthreadsWin32Base, $hashMD5=$null, $setBuildEnvVars=$true)
{
    $pthreadsWin32Url = "ftp://sourceware.org/pub/pthreads-win32/$pthreadsWin32Base.zip"
    $pthreadsWin32Path = "$ENV:Temp\$pthreadsWin32Base.zip"

    pushd .
    try
    {
        cd $buildDir
        mkdir $pthreadsWin32Base
        cd $pthreadsWin32Base

        ExecRetry { (new-object System.Net.WebClient).DownloadFile($pthreadsWin32Url, $pthreadsWin32Path) }

        if($hashMD5) { ChechFileHash $pthreadsWin32Path $hashMD5 "MD5" }

        Expand7z $pthreadsWin32Path
        del $pthreadsWin32Path

        cd "pthreads.2"

        &nmake clean VC
        if ($LastExitCode) { throw "nmake failed" }

        copy "pthreadVC2.dll" "$outputPath"

        if($setBuildEnvVars)
        {
            $ENV:INCLUDE += ";$buildDir\$pthreadsWin32Base\pthreads.2"
            $ENV:THREADS_PTHREADS_WIN32_LIBRARY = "$buildDir\$pthreadsWin32Base\pthreads.2\pthreadVC2.lib"
        }
    }
    finally
    {
        popd
    }
}
