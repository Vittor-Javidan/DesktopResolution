import type { TranslationMessages } from "./types.js";

export const enUs = {
  menu: {
    currentMode: "Current: {mode}",
    currentMarker: " (current)",
    primaryMarker: " - primary",
    resolutionLabel: "{width} x {height}{current}",
    refreshRateLabel: "{rate} Hz{current}",
    displayLabel: "{name}{primary}",
    refreshDisplays: "Refresh displays",
    quit: "Quit",
    displayQueryFailed: "Failed to query displays",
    unknownError: "Unknown error.",
    retry: "Try again",
  },
  errors: {
    invalidResolutionData: "Windows returned invalid resolution data.",
    incompleteResolutionData: "Windows returned incomplete resolution data.",
    invalidDisplayData: "Windows returned invalid display data.",
    incompleteDisplayData: "Windows returned incomplete display data.",
    unavailableCurrentMode:
      "The current display mode is not among the available options.",
    invalidDisplayList: "Windows returned an invalid list of displays.",
    noActiveDisplays: "No active displays were found.",
    emptyDisplayOutput: "The Windows utility returned no display data.",
    changeDisplayModeFailed: "Unable to change the display mode",
    trayIconLoadFailed: "Unable to load the tray icon: {path}",
    windowsOnly: "This app is available only on Windows.",
    startupDisplayLoadFailed: "Failed to load display options at startup:",
    startupFailed: "Failed to start DesktopResolution",
  },
} as const satisfies TranslationMessages;
