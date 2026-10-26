param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("list", "set")]
    [string]$Action,

    [int]$RefreshRate = 0
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

try {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace DesktopFrameRateApp
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public ushort dmSpecVersion;
        public ushort dmDriverVersion;
        public ushort dmSize;
        public ushort dmDriverExtra;
        public uint dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public uint dmDisplayOrientation;
        public uint dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public ushort dmLogPixels;
        public uint dmBitsPerPel;
        public uint dmPelsWidth;
        public uint dmPelsHeight;
        public uint dmDisplayFlags;
        public uint dmDisplayFrequency;
        public uint dmICMMethod;
        public uint dmICMIntent;
        public uint dmMediaType;
        public uint dmDitherType;
        public uint dmReserved1;
        public uint dmReserved2;
        public uint dmPanningWidth;
        public uint dmPanningHeight;
    }

    public sealed class DisplayInfo
    {
        public string DisplayName { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int CurrentHz { get; set; }
        public int[] AvailableHz { get; set; }
    }

    public static class DisplayApi
    {
        private const int DisplayDeviceAttachedToDesktop = 0x1;
        private const int DisplayDevicePrimaryDevice = 0x4;
        private const int EnumCurrentSettings = -1;
        private const uint DisplayFrequencyField = 0x00400000;
        private const uint ChangeSettingsUpdateRegistry = 0x1;
        private const uint ChangeSettingsTest = 0x2;

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "EnumDisplayDevicesW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumDisplayDevices(
            string lpDevice,
            uint iDevNum,
            ref DISPLAY_DEVICE lpDisplayDevice,
            uint dwFlags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "EnumDisplaySettingsExW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumDisplaySettingsEx(
            string lpszDeviceName,
            int iModeNum,
            ref DEVMODE lpDevMode,
            uint dwFlags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "ChangeDisplaySettingsExW", SetLastError = true)]
        private static extern int ChangeDisplaySettingsEx(
            string lpszDeviceName,
            ref DEVMODE lpDevMode,
            IntPtr hwnd,
            uint dwflags,
            IntPtr lParam);

        private static DISPLAY_DEVICE CreateDisplayDevice()
        {
            var device = new DISPLAY_DEVICE();
            device.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            device.DeviceName = new string('\0', 32);
            device.DeviceString = new string('\0', 128);
            device.DeviceID = new string('\0', 128);
            device.DeviceKey = new string('\0', 128);
            return device;
        }

        private static DEVMODE CreateDevMode()
        {
            var mode = new DEVMODE();
            mode.dmDeviceName = new string('\0', 32);
            mode.dmFormName = new string('\0', 32);
            mode.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
            return mode;
        }

        private static DISPLAY_DEVICE FindPrimaryDisplay()
        {
            for (uint index = 0; index < 64; index++)
            {
                DISPLAY_DEVICE device = CreateDisplayDevice();
                if (!EnumDisplayDevices(null, index, ref device, 0))
                {
                    break;
                }

                bool isPrimary = (device.StateFlags & DisplayDevicePrimaryDevice) != 0;
                bool isAttached = (device.StateFlags & DisplayDeviceAttachedToDesktop) != 0;
                if (isPrimary && isAttached)
                {
                    return device;
                }
            }

            throw new InvalidOperationException("Não foi possível identificar o monitor principal.");
        }

        private static DisplayInfo ReadDisplayInfo(DISPLAY_DEVICE display)
        {
            DEVMODE currentMode = CreateDevMode();
            if (!EnumDisplaySettingsEx(display.DeviceName, EnumCurrentSettings, ref currentMode, 0))
            {
                throw new InvalidOperationException("Não foi possível consultar o modo atual do monitor principal.");
            }

            if (currentMode.dmPelsWidth == 0 || currentMode.dmPelsHeight == 0 ||
                currentMode.dmDisplayFrequency <= 1 || currentMode.dmDisplayFrequency > 1000)
            {
                throw new InvalidOperationException("O driver não informou uma resolução ou taxa de atualização válida.");
            }

            int currentHz = (int)currentMode.dmDisplayFrequency;
            var rates = new SortedSet<int>();

            for (int modeIndex = 0; ; modeIndex++)
            {
                DEVMODE mode = CreateDevMode();
                if (!EnumDisplaySettingsEx(display.DeviceName, modeIndex, ref mode, 0))
                {
                    break;
                }

                bool sameResolution = mode.dmPelsWidth == currentMode.dmPelsWidth &&
                    mode.dmPelsHeight == currentMode.dmPelsHeight &&
                    mode.dmBitsPerPel == currentMode.dmBitsPerPel;
                bool hasRefreshRate = mode.dmDisplayFrequency >= 2 &&
                    mode.dmDisplayFrequency <= 1000;
                if (sameResolution && hasRefreshRate)
                {
                    rates.Add((int)mode.dmDisplayFrequency);
                }
            }

            rates.Add(currentHz);
            return new DisplayInfo
            {
                DisplayName = display.DeviceName,
                Width = (int)currentMode.dmPelsWidth,
                Height = (int)currentMode.dmPelsHeight,
                CurrentHz = currentHz,
                AvailableHz = new List<int>(rates).ToArray()
            };
        }

        private static string GetChangeError(int result)
        {
            switch (result)
            {
                case 1:
                    return "O Windows informou que a alteração exige reinicialização.";
                case -1:
                    return "O driver de vídeo não aceitou a alteração.";
                case -2:
                    return "O modo solicitado não é compatível com o monitor.";
                case -3:
                    return "O Windows não conseguiu salvar a configuração.";
                case -4:
                    return "O driver de vídeo rejeitou as opções da alteração.";
                case -5:
                    return "O Windows recebeu parâmetros inválidos para a alteração.";
                case -6:
                    return "A alteração não é compatível com a configuração de monitores.";
                default:
                    return "O Windows não conseguiu alterar a taxa de atualização (código " + result + ").";
            }
        }

        private static void ThrowIfChangeFailed(int result)
        {
            if (result != 0)
            {
                throw new InvalidOperationException(GetChangeError(result));
            }
        }

        public static DisplayInfo GetInfo()
        {
            return ReadDisplayInfo(FindPrimaryDisplay());
        }

        public static DisplayInfo SetRefreshRate(int refreshRate)
        {
            DISPLAY_DEVICE display = FindPrimaryDisplay();
            DisplayInfo info = ReadDisplayInfo(display);
            if (Array.IndexOf(info.AvailableHz, refreshRate) < 0)
            {
                throw new InvalidOperationException(
                    "A taxa solicitada não está disponível para a resolução atual do monitor principal.");
            }

            DEVMODE mode = CreateDevMode();
            if (!EnumDisplaySettingsEx(display.DeviceName, EnumCurrentSettings, ref mode, 0))
            {
                throw new InvalidOperationException("Não foi possível consultar o modo atual do monitor principal.");
            }

            mode.dmDisplayFrequency = (uint)refreshRate;
            mode.dmFields |= DisplayFrequencyField;

            int testResult = ChangeDisplaySettingsEx(
                display.DeviceName,
                ref mode,
                IntPtr.Zero,
                ChangeSettingsTest,
                IntPtr.Zero);
            ThrowIfChangeFailed(testResult);

            int applyResult = ChangeDisplaySettingsEx(
                display.DeviceName,
                ref mode,
                IntPtr.Zero,
                ChangeSettingsUpdateRegistry,
                IntPtr.Zero);
            ThrowIfChangeFailed(applyResult);

            return ReadDisplayInfo(display);
        }
    }
}
'@ -Language CSharp

    if ($Action -eq "set") {
        $display = [DesktopFrameRateApp.DisplayApi]::SetRefreshRate($RefreshRate)
    }
    else {
        $display = [DesktopFrameRateApp.DisplayApi]::GetInfo()
    }

    $result = [pscustomobject]@{
        displayName = $display.DisplayName
        width = $display.Width
        height = $display.Height
        currentHz = $display.CurrentHz
        availableHz = @($display.AvailableHz)
    }
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
