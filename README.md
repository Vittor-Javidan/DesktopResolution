# DesktopResolution

DesktopResolution is a Windows utility shortcut for viewing and changing the resolution
and refresh rate of connected displays from the system tray. It provides quick
access to display modes without opening Windows Settings.

## Display information

The app detects active displays and lists them separately in the tray menu as
**Display 1**, **Display 2**, and so on. The primary display is marked. Each
display shows its current resolution and refresh rate, along with the other
resolutions and refresh rates Windows reports as compatible with that display
at the current color depth.

The current resolution and refresh rate are marked in the menu, so you can see
which mode is active before making a change.

## Changing a display mode

Open a display's submenu, choose a resolution, then choose a refresh rate. The
app applies that combination to the selected display only, preserves its
current color depth, and leaves the other displays unchanged.

Before applying a mode, DesktopResolution checks that it is still available and
asks Windows to test its compatibility. If Windows or the display driver
rejects the change, the app shows an error. After a successful change, it
updates the display information and tray tooltip.

## Using the system tray

DesktopResolution runs in the Windows notification area without a main window.
Left- or right-click its tray icon to open the display menu. The tooltip shows
the primary display's current resolution and refresh rate.

The app reads and caches display information at startup. Use **Refresh
displays** (or **Atualizar monitores**) to query the displays and available
modes again. If the app cannot read the display information, the menu offers
an option to try again. Choose **Quit** (or **Sair**) to close the app.

The tray menu uses the first preferred system language supported by the app.
English (United States) is the default, and Brazilian Portuguese is also
included. If no supported language is detected, the app uses English.

## Adding a translation

Create a separate file for the locale, such as
[`src/translations/fr-fr.ts`](./src/translations/fr-fr.ts), and export its
messages using the `TranslationMessages` type from
[`src/translations/types.ts`](./src/translations/types.ts). Then import that
file and add its lowercase language-region code to the translations object in
[`src/translations/index.ts`](./src/translations/index.ts). TypeScript checks
that every locale provides all messages. Dynamic values use placeholders such
as `{mode}`. At startup, the app checks preferred system languages in order,
using an exact locale when available or another available locale with the same
language code. If none match, it falls back to `en-us`.

When installed, the app is configured to start automatically with Windows.
