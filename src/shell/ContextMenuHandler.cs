using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace DesktopFrameRateApp.Shell
{
    [ComVisible(true)]
    [Guid("5A691C38-06B7-44C4-A3D2-7D0EDAC74B51")]
    [ProgId("DesktopFrameRateApp.RefreshRateContextMenu")]
    [ClassInterface(ClassInterfaceType.None)]
    [ComDefaultInterface(typeof(IContextMenu))]
    public sealed class RefreshRateContextMenu : IContextMenu, IShellExtInit
    {
        private const int S_OK = 0;
        private const int E_FAIL = unchecked((int)0x80004005);
        private const int E_INVALIDARG = unchecked((int)0x80070057);
        private const int E_NOTIMPL = unchecked((int)0x80004001);
        private const uint ContextMenuDefaultOnly = 0x00000001;
        private const uint MenuItemString = 0x00000000;
        private const uint MenuItemRadioCheck = 0x00000200;
        private const uint MenuItemDisabled = 0x00000003;
        private const uint MenuItemChecked = 0x00000008;
        private const uint MenuItemMaskState = 0x00000001;
        private const uint MenuItemMaskId = 0x00000002;
        private const uint MenuItemMaskSubMenu = 0x00000004;
        private const uint MenuItemMaskType = 0x00000100;
        private const uint MenuItemMaskString = 0x00000040;

        private readonly List<int> _commandRates = new List<int>();
        private DisplayInfo _display;
        private string _error;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct MenuItemInfo
        {
            internal uint Size;
            internal uint Mask;
            internal uint Type;
            internal uint State;
            internal uint Id;
            internal IntPtr SubMenu;
            internal IntPtr CheckedBitmap;
            internal IntPtr UncheckedBitmap;
            internal UIntPtr ItemData;
            internal IntPtr TypeData;
            internal uint CharacterCount;
            internal IntPtr ItemBitmap;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CommandInfo
        {
            internal uint Size;
            internal uint Mask;
            internal IntPtr Window;
            internal IntPtr Verb;
            internal IntPtr Parameters;
            internal IntPtr Directory;
            internal int Show;
            internal uint HotKey;
            internal IntPtr Icon;
        }

        [DllImport("user32.dll")]
        private static extern IntPtr CreatePopupMenu();

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "InsertMenuItemW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool InsertMenuItem(
            IntPtr menu,
            uint item,
            [MarshalAs(UnmanagedType.Bool)] bool byPosition,
            ref MenuItemInfo menuItemInfo
        );

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DestroyMenu(IntPtr menu);

        public int Initialize(IntPtr folder, IntPtr dataObject, IntPtr registryKey)
        {
            return S_OK;
        }

        public int QueryContextMenu(
            IntPtr menu,
            uint indexMenu,
            uint idCommandFirst,
            uint idCommandLast,
            uint flags
        )
        {
            if ((flags & ContextMenuDefaultOnly) != 0)
            {
                return S_OK;
            }

            if (menu == IntPtr.Zero)
            {
                return E_INVALIDARG;
            }

            _commandRates.Clear();
            _display = null;
            _error = null;

            try
            {
                _display = DisplayApi.GetDisplayAtCursor();
                _commandRates.AddRange(_display.AvailableRefreshRates);
                long commandCapacity = (long)idCommandLast - idCommandFirst + 1;
                if (commandCapacity < _commandRates.Count)
                {
                    _commandRates.Clear();
                    _error = "Não foi possível exibir todas as taxas disponíveis.";
                }
            }
            catch (Exception error)
            {
                _error = error.Message;
            }

            IntPtr submenu = CreatePopupMenu();
            if (submenu == IntPtr.Zero)
            {
                return Marshal.GetHRForLastWin32Error();
            }

            if (_commandRates.Count > 0)
            {
                for (int index = 0; index < _commandRates.Count; index++)
                {
                    int rate = _commandRates[index];
                    string label = rate + " Hz";
                    uint state = 0;
                    if (rate == _display.CurrentRefreshRate)
                    {
                        label += " (atual)";
                        state |= MenuItemChecked;
                    }

                    uint commandId = idCommandFirst + (uint)index;
                    if (!InsertStringItem(
                        submenu,
                        (uint)index,
                        commandId,
                        MenuItemRadioCheck,
                        state,
                        label,
                        IntPtr.Zero
                    ))
                    {
                        DestroyMenu(submenu);
                        return Marshal.GetHRForLastWin32Error();
                    }
                }
            }
            else
            {
                string label = String.IsNullOrEmpty(_error)
                    ? "Não foi possível detectar o monitor."
                    : _error;
                if (!InsertStringItem(
                    submenu,
                    0,
                    0,
                    MenuItemString,
                    MenuItemDisabled,
                    label,
                    IntPtr.Zero
                ))
                {
                    DestroyMenu(submenu);
                    return Marshal.GetHRForLastWin32Error();
                }
            }

            if (!InsertStringItem(
                menu,
                indexMenu,
                0,
                MenuItemString,
                0,
                "Refresh Rate",
                submenu
            ))
            {
                DestroyMenu(submenu);
                return Marshal.GetHRForLastWin32Error();
            }

            return _commandRates.Count & 0x0000FFFF;
        }

        public int InvokeCommand(IntPtr commandInfoPointer)
        {
            if (commandInfoPointer == IntPtr.Zero)
            {
                return E_INVALIDARG;
            }

            CommandInfo commandInfo = (CommandInfo)Marshal.PtrToStructure(
                commandInfoPointer,
                typeof(CommandInfo)
            );
            long verb = commandInfo.Verb.ToInt64();
            if (verb < 0 || verb > 0xFFFF)
            {
                return E_INVALIDARG;
            }

            int commandIndex = (int)verb;
            if (_display == null || commandIndex >= _commandRates.Count)
            {
                return E_INVALIDARG;
            }

            int refreshRate = _commandRates[commandIndex];
            if (refreshRate == _display.CurrentRefreshRate)
            {
                return S_OK;
            }

            try
            {
                DisplayApi.SetRefreshRate(_display.DeviceName, refreshRate);
                return S_OK;
            }
            catch (Exception error)
            {
                DisplayApi.ShowError(
                    commandInfo.Window,
                    "Não foi possível alterar a taxa do monitor " +
                    _display.DeviceName + " para " + refreshRate + " Hz.\n\n" +
                    error.Message
                );
                return E_FAIL;
            }
        }

        public int GetCommandString(
            UIntPtr commandId,
            uint flags,
            IntPtr reserved,
            IntPtr commandString,
            uint maximumCharacters
        )
        {
            return E_NOTIMPL;
        }

        private static bool InsertStringItem(
            IntPtr menu,
            uint position,
            uint id,
            uint type,
            uint state,
            string label,
            IntPtr submenu
        )
        {
            IntPtr text = Marshal.StringToHGlobalUni(label);
            try
            {
                MenuItemInfo item = new MenuItemInfo();
                item.Size = (uint)Marshal.SizeOf(typeof(MenuItemInfo));
                item.Mask = MenuItemMaskType | MenuItemMaskString | MenuItemMaskState;
                item.Type = type;
                item.State = state;
                item.Id = id;
                item.SubMenu = submenu;
                item.TypeData = text;
                item.CharacterCount = (uint)label.Length;

                if (submenu != IntPtr.Zero)
                {
                    item.Mask |= MenuItemMaskSubMenu;
                }
                else if (type != MenuItemString || state != MenuItemDisabled)
                {
                    item.Mask |= MenuItemMaskId;
                }

                return InsertMenuItem(menu, position, true, ref item);
            }
            finally
            {
                Marshal.FreeHGlobal(text);
            }
        }
    }

    [ComVisible(true)]
    [Guid("000214E4-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IContextMenu
    {
        [PreserveSig]
        int QueryContextMenu(
            IntPtr menu,
            uint indexMenu,
            uint idCommandFirst,
            uint idCommandLast,
            uint flags
        );

        [PreserveSig]
        int InvokeCommand(IntPtr commandInfo);

        [PreserveSig]
        int GetCommandString(
            UIntPtr commandId,
            uint flags,
            IntPtr reserved,
            IntPtr commandString,
            uint maximumCharacters
        );
    }

    [ComVisible(true)]
    [Guid("000214E8-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellExtInit
    {
        [PreserveSig]
        int Initialize(IntPtr folder, IntPtr dataObject, IntPtr registryKey);
    }
}
