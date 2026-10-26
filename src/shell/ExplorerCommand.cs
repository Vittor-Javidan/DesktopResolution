using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace DesktopFrameRateApp.Shell
{
    [ComVisible(true)]
    [Guid("A08CE4D0-FA25-44AB-B57C-C7B1C323E0B9")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IExplorerCommand
    {
        [PreserveSig]
        int GetTitle(IntPtr items, out IntPtr title);

        [PreserveSig]
        int GetIcon(IntPtr items, out IntPtr icon);

        [PreserveSig]
        int GetToolTip(IntPtr items, out IntPtr toolTip);

        [PreserveSig]
        int GetCanonicalName(out Guid commandName);

        [PreserveSig]
        int GetState(IntPtr items, [MarshalAs(UnmanagedType.Bool)] bool okToBeSlow, out uint state);

        [PreserveSig]
        int Invoke(IntPtr items, IntPtr bindContext);

        [PreserveSig]
        int GetFlags(out uint flags);

        [PreserveSig]
        int EnumSubCommands(out IEnumExplorerCommand commands);
    }

    [ComVisible(true)]
    [Guid("A88826F8-186F-4987-AADE-EA0CEF8FBFE8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IEnumExplorerCommand
    {
        [PreserveSig]
        int Next(uint count, IntPtr commands, IntPtr fetchedCount);

        [PreserveSig]
        int Skip(uint count);

        [PreserveSig]
        int Reset();

        [PreserveSig]
        int Clone(out IEnumExplorerCommand enumerator);
    }

    [ComVisible(true)]
    [Guid("A2EB74E3-4B6B-41B9-A1B2-3A2B5F6D124E")]
    [ProgId("DesktopFrameRateApp.RefreshRateExplorerCommand")]
    [ClassInterface(ClassInterfaceType.None)]
    [ComDefaultInterface(typeof(IExplorerCommand))]
    public sealed class RefreshRateExplorerCommand : IExplorerCommand
    {
        private const int S_OK = 0;
        private const int E_FAIL = unchecked((int)0x80004005);
        private const int E_NOTIMPL = unchecked((int)0x80004001);
        private const uint ExplorerCommandHasSubcommands = 0x00000001;
        private const uint CommandEnabled = 0;
        private const uint CommandDisabled = 1;

        private readonly bool _isRoot;
        private readonly int _refreshRate;
        private readonly string _statusMessage;
        private readonly Guid _commandName;
        private DisplayInfo _display;
        private string _displayError;

        public RefreshRateExplorerCommand()
        {
            _isRoot = true;
            _commandName = Guid.NewGuid();
        }

        internal RefreshRateExplorerCommand(DisplayInfo display, int refreshRate)
        {
            _display = display;
            _refreshRate = refreshRate;
            _commandName = Guid.NewGuid();
        }

        internal RefreshRateExplorerCommand(string statusMessage)
        {
            _statusMessage = statusMessage;
            _commandName = Guid.NewGuid();
        }

        public int GetTitle(IntPtr items, out IntPtr title)
        {
            EnsureDisplay();
            string text;
            if (_isRoot)
            {
                text = "Refresh Rate";
            }
            else if (_statusMessage != null)
            {
                text = _statusMessage;
            }
            else if (_display != null && _refreshRate == _display.CurrentRefreshRate)
            {
                text = _refreshRate + " Hz (atual)";
            }
            else
            {
                text = _refreshRate + " Hz";
            }

            title = Marshal.StringToCoTaskMemUni(text);
            return S_OK;
        }

        public int GetIcon(IntPtr items, out IntPtr icon)
        {
            icon = IntPtr.Zero;
            return S_OK;
        }

        public int GetToolTip(IntPtr items, out IntPtr toolTip)
        {
            toolTip = IntPtr.Zero;
            return S_OK;
        }

        public int GetCanonicalName(out Guid commandName)
        {
            commandName = _commandName;
            return S_OK;
        }

        public int GetState(
            IntPtr items,
            [MarshalAs(UnmanagedType.Bool)] bool okToBeSlow,
            out uint state
        )
        {
            EnsureDisplay();
            state = !_isRoot &&
                (_statusMessage != null ||
                    (_display != null && _refreshRate == _display.CurrentRefreshRate))
                ? CommandDisabled
                : CommandEnabled;
            return S_OK;
        }

        public int Invoke(IntPtr items, IntPtr bindContext)
        {
            if (_isRoot || _statusMessage != null || _display == null)
            {
                return E_NOTIMPL;
            }

            if (_refreshRate == _display.CurrentRefreshRate)
            {
                return S_OK;
            }

            try
            {
                DisplayApi.SetRefreshRate(_display.DeviceName, _refreshRate);
                return S_OK;
            }
            catch (Exception error)
            {
                DisplayApi.ShowError(
                    IntPtr.Zero,
                    "Não foi possível alterar a taxa do monitor " +
                    _display.DeviceName + " para " + _refreshRate + " Hz.\n\n" +
                    error.Message
                );
                return E_FAIL;
            }
        }

        public int GetFlags(out uint flags)
        {
            flags = _isRoot ? ExplorerCommandHasSubcommands : 0;
            return S_OK;
        }

        public int EnumSubCommands(out IEnumExplorerCommand commands)
        {
            if (!_isRoot)
            {
                commands = null;
                return E_NOTIMPL;
            }

            EnsureDisplay();
            List<IExplorerCommand> subcommands = new List<IExplorerCommand>();
            if (_display == null)
            {
                subcommands.Add(
                    new RefreshRateExplorerCommand(
                        String.IsNullOrEmpty(_displayError)
                            ? "Monitor indisponível."
                            : _displayError
                    )
                );
            }
            else
            {
                foreach (int rate in _display.AvailableRefreshRates)
                {
                    subcommands.Add(new RefreshRateExplorerCommand(_display, rate));
                }
            }

            commands = new ExplorerCommandEnumerator(subcommands.ToArray());
            return S_OK;
        }

        private void EnsureDisplay()
        {
            if (!_isRoot || _display != null || _displayError != null)
            {
                return;
            }

            try
            {
                _display = DisplayApi.GetDisplayAtCursor();
            }
            catch (Exception error)
            {
                _displayError = error.Message;
            }
        }
    }

    internal sealed class ExplorerCommandEnumerator : IEnumExplorerCommand
    {
        private const int S_OK = 0;
        private const int S_FALSE = 1;
        private const int E_POINTER = unchecked((int)0x80004003);

        private readonly IExplorerCommand[] _commands;
        private int _position;

        internal ExplorerCommandEnumerator(IExplorerCommand[] commands)
        {
            _commands = commands;
        }

        private ExplorerCommandEnumerator(IExplorerCommand[] commands, int position)
        {
            _commands = commands;
            _position = position;
        }

        public int Next(uint count, IntPtr commands, IntPtr fetchedCount)
        {
            if (commands == IntPtr.Zero)
            {
                return E_POINTER;
            }

            uint fetched = 0;
            while (fetched < count && _position < _commands.Length)
            {
                IntPtr command = Marshal.GetComInterfaceForObject(
                    _commands[_position],
                    typeof(IExplorerCommand)
                );
                Marshal.WriteIntPtr(
                    commands,
                    checked((int)(fetched * (uint)IntPtr.Size)),
                    command
                );
                fetched++;
                _position++;
            }

            if (fetchedCount != IntPtr.Zero)
            {
                Marshal.WriteInt32(fetchedCount, (int)fetched);
            }

            return fetched == count ? S_OK : S_FALSE;
        }

        public int Skip(uint count)
        {
            int remaining = _commands.Length - _position;
            if (count > remaining)
            {
                _position = _commands.Length;
                return S_FALSE;
            }

            _position += (int)count;
            return S_OK;
        }

        public int Reset()
        {
            _position = 0;
            return S_OK;
        }

        public int Clone(out IEnumExplorerCommand enumerator)
        {
            enumerator = new ExplorerCommandEnumerator(_commands, _position);
            return S_OK;
        }
    }
}
