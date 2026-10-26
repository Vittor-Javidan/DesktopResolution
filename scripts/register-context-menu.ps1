param(
    [Parameter(Mandatory = $true)]
    [string]$AssemblyPath
)

$ErrorActionPreference = "Stop"

$resolvedAssembly = (Resolve-Path $AssemblyPath).Path
$regasm = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe"
$regExe = Join-Path $env:WINDIR "System32\reg.exe"
$legacyClsid = "{5A691C38-06B7-44C4-A3D2-7D0EDAC74B51}"
$explorerCommandClsid = "{A2EB74E3-4B6B-41B9-A1B2-3A2B5F6D124E}"
$temporaryRegFile = Join-Path $env:TEMP ("refresh-rate-" + [Guid]::NewGuid().ToString("N") + ".reg")

if (-not (Test-Path $regasm)) {
    throw "O registrador COM de 64 bits do .NET Framework não foi encontrado: $regasm"
}

if (-not (Test-Path $regExe)) {
    throw "O utilitário de registro do Windows não foi encontrado: $regExe"
}

try {
    & $regasm /nologo /codebase "/regfile:$temporaryRegFile" $resolvedAssembly
    if ($LASTEXITCODE -ne 0) {
        throw "O RegAsm falhou ao preparar o registro COM (código $LASTEXITCODE)."
    }

    $registration = [System.IO.File]::ReadAllText($temporaryRegFile)
    $registration = $registration.Replace(
        "HKEY_CLASSES_ROOT",
        "HKEY_CURRENT_USER\Software\Classes"
    )
    [System.IO.File]::WriteAllText(
        $temporaryRegFile,
        $registration,
        [System.Text.Encoding]::Unicode
    )

    & $regExe import $temporaryRegFile
    if ($LASTEXITCODE -ne 0) {
        throw "O Windows falhou ao registrar a extensão COM (código $LASTEXITCODE)."
    }

    $classes = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::CurrentUser,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    try {
        $modernCommand = $classes.CreateSubKey(
            "Software\Classes\DesktopBackground\Shell\RefreshRate"
        )
        try {
            $modernCommand.SetValue("MUIVerb", "Refresh Rate")
            $modernCommand.SetValue("ExplorerCommandHandler", $explorerCommandClsid)
        }
        finally {
            $modernCommand.Dispose()
        }

        $classicCommand = $classes.CreateSubKey(
            "Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\RefreshRate"
        )
        try {
            $classicCommand.SetValue("", $legacyClsid)
        }
        finally {
            $classicCommand.Dispose()
        }
    }
    finally {
        $classes.Dispose()
    }
}
finally {
    Remove-Item $temporaryRegFile -Force -ErrorAction SilentlyContinue
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RefreshRateShellNotification
{
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(
        int eventId,
        uint flags,
        IntPtr item1,
        IntPtr item2);
}
'@
[RefreshRateShellNotification]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

Write-Output "O submenu Refresh Rate foi registrado para o usuário atual."
