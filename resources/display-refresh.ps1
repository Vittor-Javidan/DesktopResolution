param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("list", "set")]
    [string]$Action,

    [string]$DeviceName,
    [int]$Width = 0,
    [int]$Height = 0,
    [int]$RefreshRate = 0
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

try {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
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

    public sealed class ResolutionInfo
    {
        public int Width { get; set; }
        public int Height { get; set; }
        public int[] AvailableRefreshRates { get; set; }
    }

    public sealed class DisplayInfo
    {
        public string DeviceName { get; set; }
        public string DisplayName { get; set; }
        public bool IsPrimary { get; set; }
        public int CurrentWidth { get; set; }
        public int CurrentHeight { get; set; }
        public int CurrentRefreshRate { get; set; }
        public ResolutionInfo[] AvailableResolutions { get; set; }
    }

    public static class DisplayApi
    {
        private const int DisplayDeviceAttachedToDesktop = 0x1;
        private const int DisplayDevicePrimaryDevice = 0x4;
        private const int DisplayDeviceMirroringDriver = 0x8;
        private const int EnumCurrentSettings = -1;
        private const uint DmBitsPerPel = 0x00040000;
        private const uint DmPelsWidth = 0x00080000;
        private const uint DmPelsHeight = 0x00100000;
        private const uint DmDisplayFrequency = 0x00400000;
        private const uint ChangeSettingsUpdateRegistry = 0x1;
        private const uint ChangeSettingsTest = 0x2;

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "EnumDisplayDevicesW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumDisplayDevices(
            string deviceName,
            uint deviceNumber,
            ref DISPLAY_DEVICE displayDevice,
            uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "EnumDisplaySettingsExW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumDisplaySettingsEx(
            string deviceName,
            int modeNumber,
            ref DEVMODE displayMode,
            uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "ChangeDisplaySettingsExW", SetLastError = true)]
        private static extern int ChangeDisplaySettingsEx(
            string deviceName,
            ref DEVMODE displayMode,
            IntPtr window,
            uint flags,
            IntPtr parameter);

        private sealed class DisplayDeviceInfo
        {
            internal string DeviceName;
            internal string DisplayName;
            internal bool IsPrimary;
        }

        private sealed class ResolutionBuilder
        {
            internal int Width;
            internal int Height;
            internal SortedSet<int> RefreshRates = new SortedSet<int>();
        }

        private static DISPLAY_DEVICE CreateDisplayDevice()
        {
            DISPLAY_DEVICE device = new DISPLAY_DEVICE();
            device.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            device.DeviceName = new string('\0', 32);
            device.DeviceString = new string('\0', 128);
            device.DeviceID = new string('\0', 128);
            device.DeviceKey = new string('\0', 128);
            return device;
        }

        private static DEVMODE CreateDevMode()
        {
            DEVMODE mode = new DEVMODE();
            mode.dmDeviceName = new string('\0', 32);
            mode.dmFormName = new string('\0', 32);
            mode.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
            return mode;
        }

        private static List<DisplayDeviceInfo> EnumerateDisplays()
        {
            List<DisplayDeviceInfo> displays = new List<DisplayDeviceInfo>();
            for (uint index = 0; index < 64; index++)
            {
                DISPLAY_DEVICE device = CreateDisplayDevice();
                if (!EnumDisplayDevices(null, index, ref device, 0))
                {
                    break;
                }

                bool isAttached = (device.StateFlags & DisplayDeviceAttachedToDesktop) != 0;
                bool isMirroring = (device.StateFlags & DisplayDeviceMirroringDriver) != 0;
                if (!isAttached || isMirroring || String.IsNullOrWhiteSpace(device.DeviceName))
                {
                    continue;
                }

                displays.Add(new DisplayDeviceInfo
                {
                    DeviceName = device.DeviceName,
                    DisplayName = GetDisplayName(device.DeviceName),
                    IsPrimary = (device.StateFlags & DisplayDevicePrimaryDevice) != 0
                });
            }

            return displays;
        }

        private static string GetDisplayName(string deviceName)
        {
            const string prefix = @"\\.\DISPLAY";
            if (!deviceName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    "O Windows retornou um identificador de monitor inválido: " + deviceName + "."
                );
            }

            string displayNumber = deviceName.Substring(prefix.Length);
            if (displayNumber.Length == 0)
            {
                throw new InvalidOperationException(
                    "O Windows não informou o número do monitor: " + deviceName + "."
                );
            }

            for (int index = 0; index < displayNumber.Length; index++)
            {
                if (displayNumber[index] < '0' || displayNumber[index] > '9')
                {
                    throw new InvalidOperationException(
                        "O Windows retornou um número de monitor inválido: " + deviceName + "."
                    );
                }
            }

            return "Display " + displayNumber;
        }

        private static DEVMODE GetCurrentMode(string deviceName)
        {
            DEVMODE mode = CreateDevMode();
            if (!EnumDisplaySettingsEx(deviceName, EnumCurrentSettings, ref mode, 0))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Não foi possível consultar o modo atual do monitor " + deviceName + "."
                );
            }

            if (mode.dmPelsWidth == 0 || mode.dmPelsHeight == 0 ||
                mode.dmBitsPerPel == 0 ||
                mode.dmDisplayFrequency < 2 || mode.dmDisplayFrequency > 1000)
            {
                throw new InvalidOperationException(
                    "O driver não informou um modo válido para o monitor " + deviceName + "."
                );
            }

            return mode;
        }

        private static DEVMODE CreateRequestedMode(
            DEVMODE currentMode,
            uint width,
            uint height,
            uint refreshRate)
        {
            DEVMODE mode = currentMode;
            mode.dmPelsWidth = width;
            mode.dmPelsHeight = height;
            mode.dmDisplayFrequency = refreshRate;
            mode.dmFields = DmBitsPerPel | DmPelsWidth | DmPelsHeight | DmDisplayFrequency;
            return mode;
        }

        private static bool IsModeCompatible(
            string deviceName,
            DEVMODE currentMode,
            uint width,
            uint height,
            uint refreshRate)
        {
            DEVMODE mode = CreateRequestedMode(currentMode, width, height, refreshRate);
            int result = ChangeDisplaySettingsEx(
                deviceName,
                ref mode,
                IntPtr.Zero,
                ChangeSettingsTest,
                IntPtr.Zero
            );
            return result == 0;
        }

        private static DisplayInfo ReadDisplayInfo(DisplayDeviceInfo display)
        {
            DEVMODE currentMode = GetCurrentMode(display.DeviceName);
            int currentWidth = checked((int)currentMode.dmPelsWidth);
            int currentHeight = checked((int)currentMode.dmPelsHeight);
            int currentRefreshRate = (int)currentMode.dmDisplayFrequency;
            Dictionary<string, ResolutionBuilder> resolutions =
                new Dictionary<string, ResolutionBuilder>();

            for (int modeNumber = 0; modeNumber < 4096; modeNumber++)
            {
                DEVMODE mode = CreateDevMode();
                if (!EnumDisplaySettingsEx(display.DeviceName, modeNumber, ref mode, 0))
                {
                    break;
                }

                if (mode.dmBitsPerPel != currentMode.dmBitsPerPel ||
                    mode.dmPelsWidth == 0 || mode.dmPelsHeight == 0 ||
                    mode.dmDisplayFrequency < 2 || mode.dmDisplayFrequency > 1000)
                {
                    continue;
                }

                if (!IsModeCompatible(
                    display.DeviceName,
                    currentMode,
                    mode.dmPelsWidth,
                    mode.dmPelsHeight,
                    mode.dmDisplayFrequency))
                {
                    continue;
                }

                int width = checked((int)mode.dmPelsWidth);
                int height = checked((int)mode.dmPelsHeight);
                string key = width.ToString() + "x" + height.ToString();
                ResolutionBuilder resolution;
                if (!resolutions.TryGetValue(key, out resolution))
                {
                    resolution = new ResolutionBuilder
                    {
                        Width = width,
                        Height = height
                    };
                    resolutions.Add(key, resolution);
                }

                resolution.RefreshRates.Add((int)mode.dmDisplayFrequency);
            }

            string currentKey = currentWidth.ToString() + "x" + currentHeight.ToString();
            ResolutionBuilder currentResolution;
            if (!resolutions.TryGetValue(currentKey, out currentResolution))
            {
                currentResolution = new ResolutionBuilder
                {
                    Width = currentWidth,
                    Height = currentHeight
                };
                resolutions.Add(currentKey, currentResolution);
            }
            currentResolution.RefreshRates.Add(currentRefreshRate);

            List<ResolutionInfo> availableResolutions = new List<ResolutionInfo>();
            foreach (ResolutionBuilder resolution in resolutions.Values)
            {
                List<int> rates = new List<int>(resolution.RefreshRates);
                availableResolutions.Add(new ResolutionInfo
                {
                    Width = resolution.Width,
                    Height = resolution.Height,
                    AvailableRefreshRates = rates.ToArray()
                });
            }

            availableResolutions.Sort(delegate(ResolutionInfo left, ResolutionInfo right)
            {
                long leftPixels = (long)left.Width * left.Height;
                long rightPixels = (long)right.Width * right.Height;
                int pixelComparison = rightPixels.CompareTo(leftPixels);
                if (pixelComparison != 0)
                {
                    return pixelComparison;
                }

                int widthComparison = right.Width.CompareTo(left.Width);
                return widthComparison != 0
                    ? widthComparison
                    : right.Height.CompareTo(left.Height);
            });

            return new DisplayInfo
            {
                DeviceName = display.DeviceName,
                DisplayName = display.DisplayName,
                IsPrimary = display.IsPrimary,
                CurrentWidth = currentWidth,
                CurrentHeight = currentHeight,
                CurrentRefreshRate = currentRefreshRate,
                AvailableResolutions = availableResolutions.ToArray()
            };
        }

        private static DisplayDeviceInfo FindDisplay(string deviceName)
        {
            foreach (DisplayDeviceInfo display in EnumerateDisplays())
            {
                if (String.Equals(display.DeviceName, deviceName, StringComparison.OrdinalIgnoreCase))
                {
                    return display;
                }
            }

            throw new InvalidOperationException(
                "O monitor " + deviceName + " não está mais conectado."
            );
        }

        private static string GetChangeError(int result)
        {
            switch (result)
            {
                case 1:
                    return "A alteração exige reinicialização.";
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
                    return "O Windows não conseguiu alterar o modo de exibição (código " +
                        result.ToString() + ").";
            }
        }

        private static void ThrowIfChangeFailed(int result)
        {
            if (result != 0)
            {
                throw new InvalidOperationException(GetChangeError(result));
            }
        }

        public static DisplayInfo[] GetDisplays()
        {
            List<DisplayInfo> displays = new List<DisplayInfo>();
            foreach (DisplayDeviceInfo display in EnumerateDisplays())
            {
                displays.Add(ReadDisplayInfo(display));
            }

            return displays.ToArray();
        }

        public static void SetDisplayMode(
            string deviceName,
            int width,
            int height,
            int refreshRate)
        {
            if (String.IsNullOrWhiteSpace(deviceName) ||
                width <= 0 || height <= 0 ||
                refreshRate < 2 || refreshRate > 1000)
            {
                throw new ArgumentException("A resolução ou taxa solicitada é inválida.");
            }

            DisplayDeviceInfo display = FindDisplay(deviceName);
            DisplayInfo info = ReadDisplayInfo(display);
            bool isAvailable = false;
            foreach (ResolutionInfo resolution in info.AvailableResolutions)
            {
                if (resolution.Width == width && resolution.Height == height &&
                    Array.IndexOf(resolution.AvailableRefreshRates, refreshRate) >= 0)
                {
                    isAvailable = true;
                    break;
                }
            }

            if (!isAvailable)
            {
                throw new InvalidOperationException(
                    "A resolução " + width.ToString() + " x " + height.ToString() +
                    " a " + refreshRate.ToString() + " Hz não está disponível para " +
                    display.DisplayName + "."
                );
            }

            DEVMODE mode = CreateRequestedMode(
                GetCurrentMode(display.DeviceName),
                (uint)width,
                (uint)height,
                (uint)refreshRate
            );

            int testResult = ChangeDisplaySettingsEx(
                display.DeviceName,
                ref mode,
                IntPtr.Zero,
                ChangeSettingsTest,
                IntPtr.Zero
            );
            ThrowIfChangeFailed(testResult);

            int applyResult = ChangeDisplaySettingsEx(
                display.DeviceName,
                ref mode,
                IntPtr.Zero,
                ChangeSettingsUpdateRegistry,
                IntPtr.Zero
            );
            ThrowIfChangeFailed(applyResult);

            DisplayInfo updatedDisplay = ReadDisplayInfo(display);
            if (updatedDisplay.CurrentWidth != width ||
                updatedDisplay.CurrentHeight != height ||
                updatedDisplay.CurrentRefreshRate != refreshRate)
            {
                throw new InvalidOperationException(
                    "O Windows informou que a alteração foi aplicada, mas o monitor " +
                    display.DisplayName + " continua em " +
                    updatedDisplay.CurrentWidth.ToString() + " x " +
                    updatedDisplay.CurrentHeight.ToString() + " a " +
                    updatedDisplay.CurrentRefreshRate.ToString() + " Hz."
                );
            }
        }
    }
}
'@ -Language CSharp

    if ($Action -eq "set") {
        if ([string]::IsNullOrWhiteSpace($DeviceName) -or
            $Width -le 0 -or $Height -le 0 -or $RefreshRate -le 0) {
            throw "Informe o monitor, a resolução e a taxa de atualização para aplicar."
        }

        [DesktopFrameRateApp.DisplayApi]::SetDisplayMode(
            $DeviceName,
            $Width,
            $Height,
            $RefreshRate
        )
    }

    $displayList = @(
        foreach ($display in [DesktopFrameRateApp.DisplayApi]::GetDisplays()) {
            $resolutionList = @(
                foreach ($resolution in $display.AvailableResolutions) {
                    [pscustomobject]@{
                        width = $resolution.Width
                        height = $resolution.Height
                        availableRefreshRates = @($resolution.AvailableRefreshRates)
                    }
                }
            )

            [pscustomobject]@{
                deviceName = $display.DeviceName
                displayName = $display.DisplayName
                isPrimary = $display.IsPrimary
                currentWidth = $display.CurrentWidth
                currentHeight = $display.CurrentHeight
                currentRefreshRate = $display.CurrentRefreshRate
                availableResolutions = $resolutionList
            }
        }
    )

    $result = [pscustomobject]@{
        displays = $displayList
    }
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
