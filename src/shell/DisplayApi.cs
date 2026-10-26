using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Reflection;
using System.Runtime.InteropServices;

[assembly: AssemblyTitle("Refresh Rate Shell Extension")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: ComVisible(false)]

namespace DesktopFrameRateApp.Shell
{
    internal sealed class DisplayInfo
    {
        internal string DeviceName;
        internal int Width;
        internal int Height;
        internal int BitsPerPixel;
        internal int CurrentRefreshRate;
        internal List<int> AvailableRefreshRates;
    }

    internal static class DisplayApi
    {
        private const int MonitorDefaultToNearest = 2;
        private const int EnumCurrentSettings = -1;
        private const uint DisplayFrequencyField = 0x00400000;
        private const uint ChangeSettingsUpdateRegistry = 0x00000001;
        private const uint ChangeSettingsTest = 0x00000002;

        [StructLayout(LayoutKind.Sequential)]
        private struct Point
        {
            internal int X;
            internal int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect
        {
            internal int Left;
            internal int Top;
            internal int Right;
            internal int Bottom;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct MonitorInfoEx
        {
            internal int Size;
            internal Rect Monitor;
            internal Rect Work;
            internal uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            internal string DeviceName;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DevMode
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            internal string DeviceName;
            internal ushort SpecVersion;
            internal ushort DriverVersion;
            internal ushort Size;
            internal ushort DriverExtra;
            internal uint Fields;
            internal int PositionX;
            internal int PositionY;
            internal uint DisplayOrientation;
            internal uint DisplayFixedOutput;
            internal short Color;
            internal short Duplex;
            internal short YResolution;
            internal short TTOption;
            internal short Collate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            internal string FormName;
            internal ushort LogPixels;
            internal uint BitsPerPixel;
            internal uint PelsWidth;
            internal uint PelsHeight;
            internal uint DisplayFlags;
            internal uint DisplayFrequency;
            internal uint ICMMethod;
            internal uint ICMIntent;
            internal uint MediaType;
            internal uint DitherType;
            internal uint Reserved1;
            internal uint Reserved2;
            internal uint PanningWidth;
            internal uint PanningHeight;
        }

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetCursorPos(ref Point point);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromPoint(
            Point point,
            int flags
        );

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetMonitorInfoW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetMonitorInfo(
            IntPtr monitor,
            ref MonitorInfoEx info
        );

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "EnumDisplaySettingsExW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumDisplaySettings(
            string deviceName,
            int modeNumber,
            ref DevMode mode,
            uint flags
        );

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "ChangeDisplaySettingsExW", SetLastError = true)]
        private static extern int ChangeDisplaySettings(
            string deviceName,
            ref DevMode mode,
            IntPtr window,
            uint flags,
            IntPtr parameter
        );

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "MessageBoxW")]
        private static extern int MessageBox(
            IntPtr window,
            string text,
            string caption,
            uint type
        );

        internal static DisplayInfo GetDisplayAtCursor()
        {
            Point point = new Point();
            if (!GetCursorPos(ref point))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Não foi possível determinar a posição do clique."
                );
            }

            IntPtr monitor = MonitorFromPoint(point, MonitorDefaultToNearest);
            if (monitor == IntPtr.Zero)
            {
                throw new InvalidOperationException(
                    "Não foi possível identificar o monitor sob o ponteiro."
                );
            }

            MonitorInfoEx info = new MonitorInfoEx();
            info.Size = Marshal.SizeOf(typeof(MonitorInfoEx));
            info.DeviceName = new string('\0', 32);
            if (!GetMonitorInfo(monitor, ref info))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Não foi possível consultar o monitor sob o ponteiro."
                );
            }

            return GetDisplay(info.DeviceName);
        }

        internal static DisplayInfo GetDisplay(string deviceName)
        {
            DevMode currentMode = CreateDevMode();
            if (!EnumDisplaySettings(deviceName, EnumCurrentSettings, ref currentMode, 0))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Não foi possível consultar o modo atual do monitor " + deviceName + "."
                );
            }

            if (
                currentMode.PelsWidth == 0 ||
                currentMode.PelsHeight == 0 ||
                currentMode.DisplayFrequency < 2 ||
                currentMode.DisplayFrequency > 1000
            )
            {
                throw new InvalidOperationException(
                    "O driver não informou uma resolução ou taxa de atualização válida para " +
                    deviceName + "."
                );
            }

            List<int> rates = new List<int>();
            for (int modeNumber = 0; modeNumber < 4096; modeNumber++)
            {
                DevMode mode = CreateDevMode();
                if (!EnumDisplaySettings(deviceName, modeNumber, ref mode, 0))
                {
                    break;
                }

                bool sameMode = mode.PelsWidth == currentMode.PelsWidth &&
                    mode.PelsHeight == currentMode.PelsHeight &&
                    mode.BitsPerPixel == currentMode.BitsPerPixel;
                bool hasValidRate = mode.DisplayFrequency >= 2 &&
                    mode.DisplayFrequency <= 1000;
                int refreshRate = (int)mode.DisplayFrequency;

                if (sameMode && hasValidRate && !rates.Contains(refreshRate))
                {
                    rates.Add(refreshRate);
                }
            }

            int currentRefreshRate = (int)currentMode.DisplayFrequency;
            if (!rates.Contains(currentRefreshRate))
            {
                rates.Add(currentRefreshRate);
            }
            rates.Sort();

            return new DisplayInfo
            {
                DeviceName = deviceName,
                Width = (int)currentMode.PelsWidth,
                Height = (int)currentMode.PelsHeight,
                BitsPerPixel = (int)currentMode.BitsPerPixel,
                CurrentRefreshRate = currentRefreshRate,
                AvailableRefreshRates = rates
            };
        }

        internal static void SetRefreshRate(string deviceName, int refreshRate)
        {
            DisplayInfo display = GetDisplay(deviceName);
            if (!display.AvailableRefreshRates.Contains(refreshRate))
            {
                throw new InvalidOperationException(
                    "A taxa de " + refreshRate +
                    " Hz não está disponível para a resolução atual do monitor " +
                    deviceName + "."
                );
            }

            DevMode mode = CreateDevMode();
            if (!EnumDisplaySettings(deviceName, EnumCurrentSettings, ref mode, 0))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Não foi possível consultar o modo atual do monitor " + deviceName + "."
                );
            }

            mode.DisplayFrequency = (uint)refreshRate;
            mode.Fields |= DisplayFrequencyField;

            int testResult = ChangeDisplaySettings(
                deviceName,
                ref mode,
                IntPtr.Zero,
                ChangeSettingsTest,
                IntPtr.Zero
            );
            ThrowIfChangeFailed(testResult);

            int applyResult = ChangeDisplaySettings(
                deviceName,
                ref mode,
                IntPtr.Zero,
                ChangeSettingsUpdateRegistry,
                IntPtr.Zero
            );
            ThrowIfChangeFailed(applyResult);

            DisplayInfo updatedDisplay = GetDisplay(deviceName);
            if (updatedDisplay.CurrentRefreshRate != refreshRate)
            {
                throw new InvalidOperationException(
                    "O Windows informou que a alteração foi aplicada, mas o monitor " +
                    deviceName + " continua em " +
                    updatedDisplay.CurrentRefreshRate + " Hz."
                );
            }
        }

        internal static void ShowError(IntPtr owner, string message)
        {
            MessageBox(owner, message, "Desktop Frame Rate App", 0x00000010);
        }

        private static DevMode CreateDevMode()
        {
            DevMode mode = new DevMode();
            mode.DeviceName = new string('\0', 32);
            mode.FormName = new string('\0', 32);
            mode.Size = (ushort)Marshal.SizeOf(typeof(DevMode));
            return mode;
        }

        private static void ThrowIfChangeFailed(int result)
        {
            if (result == 0)
            {
                return;
            }

            string message;
            switch (result)
            {
                case 1:
                    message = "A alteração exige reinicialização.";
                    break;
                case -1:
                    message = "O driver de vídeo não aceitou a alteração.";
                    break;
                case -2:
                    message = "O modo solicitado não é compatível com o monitor.";
                    break;
                case -3:
                    message = "O Windows não conseguiu salvar a configuração.";
                    break;
                case -4:
                    message = "O driver de vídeo rejeitou as opções da alteração.";
                    break;
                case -5:
                    message = "O Windows recebeu parâmetros inválidos para a alteração.";
                    break;
                case -6:
                    message = "A alteração não é compatível com a configuração de monitores.";
                    break;
                default:
                    message = "O Windows não conseguiu alterar a taxa de atualização (código " +
                        result + ").";
                    break;
            }

            throw new InvalidOperationException(message);
        }
    }
}
