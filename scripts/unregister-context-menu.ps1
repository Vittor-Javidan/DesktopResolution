$ErrorActionPreference = "Stop"

$paths = @(
    "Software\Classes\DesktopBackground\Shell\RefreshRate",
    "Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\RefreshRate",
    "Software\Classes\CLSID\{5A691C38-06B7-44C4-A3D2-7D0EDAC74B51}",
    "Software\Classes\CLSID\{A2EB74E3-4B6B-41B9-A1B2-3A2B5F6D124E}",
    "Software\Classes\DesktopFrameRateApp.RefreshRateContextMenu",
    "Software\Classes\DesktopFrameRateApp.RefreshRateExplorerCommand"
)

$classes = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::CurrentUser,
    [Microsoft.Win32.RegistryView]::Registry64
)
try {
    foreach ($path in $paths) {
        $classes.DeleteSubKeyTree($path, $false)
    }
}
finally {
    $classes.Dispose()
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

Write-Output "O submenu Refresh Rate foi removido do usuário atual."
