import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  formatTranslation,
  resolveLocale,
  translations,
  type TranslationDictionary,
} from "./translations/index.js";
import {
  app,
  dialog,
  Menu,
  nativeImage,
  Tray,
  type MenuItemConstructorOptions,
} from "electron";

type ResolutionInfo = {
  width: number;
  height: number;
  availableRefreshRates: number[];
};

type DisplayInfo = {
  deviceName: string;
  displayName: string;
  isPrimary: boolean;
  currentWidth: number;
  currentHeight: number;
  currentRefreshRate: number;
  availableResolutions: ResolutionInfo[];
};

type DisplayAction =
  | { type: "list" }
  | {
      type: "set";
      deviceName: string;
      width: number;
      height: number;
      refreshRate: number;
    };

const executeFile = promisify(execFile);
let tray: Tray | undefined;
let isLoadingMenu = false;
let currentTranslations: TranslationDictionary = translations["en-us"];
let cachedDisplays: DisplayInfo[] | undefined;
let displayCacheVersion = 0;
let displayListPromise: Promise<DisplayInfo[]> | undefined;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

function isRefreshRate(value: unknown): value is number {
  return isPositiveInteger(value) && value >= 2 && value <= 1000;
}

function parseResolutionInfo(value: unknown): ResolutionInfo {
  if (!isRecord(value)) {
    throw new Error(currentTranslations.errors.invalidResolutionData);
  }

  const { width, height, availableRefreshRates } = value;
  if (
    !isPositiveInteger(width) ||
    !isPositiveInteger(height) ||
    !Array.isArray(availableRefreshRates) ||
    availableRefreshRates.length === 0 ||
    !availableRefreshRates.every(isRefreshRate)
  ) {
    throw new Error(currentTranslations.errors.incompleteResolutionData);
  }

  return {
    width,
    height,
    availableRefreshRates: Array.from(new Set(availableRefreshRates)).sort(
      (left, right) => left - right,
    ),
  };
}

function parseDisplayInfo(value: unknown): DisplayInfo {
  if (!isRecord(value)) {
    throw new Error(currentTranslations.errors.invalidDisplayData);
  }

  const {
    deviceName,
    displayName,
    isPrimary,
    currentWidth,
    currentHeight,
    currentRefreshRate,
    availableResolutions,
  } = value;
  if (
    typeof deviceName !== "string" ||
    !deviceName.trim() ||
    typeof displayName !== "string" ||
    !displayName.trim() ||
    typeof isPrimary !== "boolean" ||
    !isPositiveInteger(currentWidth) ||
    !isPositiveInteger(currentHeight) ||
    !isRefreshRate(currentRefreshRate) ||
    !Array.isArray(availableResolutions) ||
    availableResolutions.length === 0
  ) {
    throw new Error(currentTranslations.errors.incompleteDisplayData);
  }

  const parsedResolutions = availableResolutions.map(parseResolutionInfo);
  const currentResolution = parsedResolutions.find(
    (resolution) =>
      resolution.width === currentWidth && resolution.height === currentHeight,
  );
  if (
    !currentResolution?.availableRefreshRates.includes(currentRefreshRate)
  ) {
    throw new Error(currentTranslations.errors.unavailableCurrentMode);
  }

  return {
    deviceName,
    displayName,
    isPrimary,
    currentWidth,
    currentHeight,
    currentRefreshRate,
    availableResolutions: parsedResolutions,
  };
}

function parseDisplayList(value: unknown): DisplayInfo[] {
  if (!isRecord(value) || !Array.isArray(value.displays)) {
    throw new Error(currentTranslations.errors.invalidDisplayList);
  }
  if (value.displays.length === 0) {
    throw new Error(currentTranslations.errors.noActiveDisplays);
  }

  return value.displays.map(parseDisplayInfo);
}

function getResourcePath(fileName: string): string {
  return app.isPackaged
    ? path.join(process.resourcesPath, fileName)
    : path.join(app.getAppPath(), "resources", fileName);
}

async function executeDisplayAction(action: DisplayAction): Promise<DisplayInfo[]> {
  const args = [
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    getResourcePath("display-refresh.ps1"),
    "-Action",
    action.type,
  ];

  if (action.type === "set") {
    args.push(
      "-DeviceName",
      action.deviceName,
      "-Width",
      String(action.width),
      "-Height",
      String(action.height),
      "-RefreshRate",
      String(action.refreshRate),
    );
  }

  const { stdout } = await executeFile("powershell.exe", args, {
    encoding: "utf8",
    windowsHide: true,
    timeout: 30_000,
    maxBuffer: 4_194_304,
  });
  const output = stdout.trim();
  if (!output) {
    throw new Error(currentTranslations.errors.emptyDisplayOutput);
  }

  return parseDisplayList(JSON.parse(output) as unknown);
}

function getErrorMessage(error: unknown): string {
  if (isRecord(error)) {
    if (typeof error.stderr === "string" && error.stderr.trim()) {
      return error.stderr.trim();
    }
    if (typeof error.message === "string") {
      return error.message;
    }
  }

  return String(error);
}

function formatCurrentMode(display: DisplayInfo): string {
  return `${display.currentWidth} x ${display.currentHeight} - ${display.currentRefreshRate} Hz`;
}

function updateTrayToolTip(displays: DisplayInfo[]): void {
  if (!tray) {
    return;
  }

  const primaryDisplay =
    displays.find((display) => display.isPrimary) ?? displays[0];
  tray.setToolTip(
    primaryDisplay
      ? `${primaryDisplay.displayName}: ${formatCurrentMode(primaryDisplay)}`
      : "DesktopResolution",
  );
}

function updateDisplayCache(displays: DisplayInfo[]): void {
  cachedDisplays = displays;
  displayCacheVersion += 1;
  updateTrayToolTip(displays);
}

function refreshDisplayCache(): Promise<DisplayInfo[]> {
  if (displayListPromise) {
    return displayListPromise;
  }

  const cacheVersion = displayCacheVersion;
  const refreshPromise = executeDisplayAction({ type: "list" })
    .then((displays) => {
      if (cacheVersion === displayCacheVersion) {
        updateDisplayCache(displays);
      }
      return cachedDisplays ?? displays;
    })
    .finally(() => {
      if (displayListPromise === refreshPromise) {
        displayListPromise = undefined;
      }
    });
  displayListPromise = refreshPromise;
  return refreshPromise;
}

function createDisplayMenuItem(display: DisplayInfo): MenuItemConstructorOptions {
  const { menu } = currentTranslations;
  const resolutionItems = display.availableResolutions.map(
    (resolution): MenuItemConstructorOptions => {
      const isCurrentResolution =
        resolution.width === display.currentWidth &&
        resolution.height === display.currentHeight;

      return {
        label: formatTranslation(menu.resolutionLabel, {
          width: resolution.width,
          height: resolution.height,
          current: isCurrentResolution ? menu.currentMarker : "",
        }),
        submenu: resolution.availableRefreshRates.map(
          (rate): MenuItemConstructorOptions => {
            const isCurrentMode =
              isCurrentResolution && rate === display.currentRefreshRate;

            return {
              label: formatTranslation(menu.refreshRateLabel, {
                rate,
                current: isCurrentMode ? menu.currentMarker : "",
              }),
              type: "radio",
              checked: isCurrentMode,
              click: () => {
                if (!isCurrentMode) {
                  void changeDisplayMode(
                    display.deviceName,
                    resolution.width,
                    resolution.height,
                    rate,
                  );
                }
              },
            };
          },
        ),
      };
    },
  );

  return {
    label: formatTranslation(menu.displayLabel, {
      name: display.displayName,
      primary: display.isPrimary ? menu.primaryMarker : "",
    }),
    submenu: [
      {
        label: formatTranslation(menu.currentMode, {
          mode: formatCurrentMode(display),
        }),
        enabled: false,
      },
      { type: "separator" },
      ...resolutionItems,
    ],
  };
}

function createDisplayMenu(displays: DisplayInfo[]): Menu {
  const { menu } = currentTranslations;
  return Menu.buildFromTemplate([
    ...displays.map(createDisplayMenuItem),
    { type: "separator" },
    {
      label: menu.refreshDisplays,
      click: () => {
        void openDisplayMenu(true);
      },
    },
    { label: menu.quit, role: "quit" },
  ]);
}

function createErrorMenu(error: unknown): Menu {
  const { menu } = currentTranslations;
  const details = getErrorMessage(error).replace(/\s+/g, " ").slice(0, 160);

  return Menu.buildFromTemplate([
    { label: menu.displayQueryFailed, enabled: false },
    { label: details || menu.unknownError, enabled: false },
    { type: "separator" },
    {
      label: menu.retry,
      click: () => {
        void openDisplayMenu(true);
      },
    },
    { label: menu.quit, role: "quit" },
  ]);
}

function openDisplayMenu(forceRefresh = false): void {
  const currentTray = tray;
  if (!currentTray) {
    return;
  }

  if (!forceRefresh && cachedDisplays) {
    currentTray.popUpContextMenu(createDisplayMenu(cachedDisplays));
    return;
  }

  if (isLoadingMenu) {
    return;
  }

  isLoadingMenu = true;
  void refreshDisplayCache()
    .then((displays) => {
      if (tray === currentTray) {
        currentTray.popUpContextMenu(createDisplayMenu(displays));
      }
    })
    .catch((error: unknown) => {
      if (tray === currentTray) {
        currentTray.popUpContextMenu(createErrorMenu(error));
      }
    })
    .finally(() => {
      isLoadingMenu = false;
    });
}

async function changeDisplayMode(
  deviceName: string,
  width: number,
  height: number,
  refreshRate: number,
): Promise<void> {
  try {
    const displays = await executeDisplayAction({
      type: "set",
      deviceName,
      width,
      height,
      refreshRate,
    });
    updateDisplayCache(displays);
  } catch (error) {
    dialog.showErrorBox(
      currentTranslations.errors.changeDisplayModeFailed,
      getErrorMessage(error),
    );
  }
}

function createTray(): void {
  const iconPath = app.isPackaged
    ? path.join(process.resourcesPath, "tray.png")
    : path.join(app.getAppPath(), "assets", "tray.png");
  const icon = nativeImage.createFromPath(iconPath);
  if (icon.isEmpty()) {
    throw new Error(
      formatTranslation(currentTranslations.errors.trayIconLoadFailed, {
        path: iconPath,
      }),
    );
  }

  tray = new Tray(icon);
  tray.setToolTip("DesktopResolution");
  tray.on("click", () => {
    void openDisplayMenu();
  });
  tray.on("right-click", () => {
    void openDisplayMenu();
  });
}

app.on("before-quit", () => {
  tray?.destroy();
  tray = undefined;
});

void app
  .whenReady()
  .then(() => {
    currentTranslations =
      translations[resolveLocale(app.getPreferredSystemLanguages())];

    if (process.platform !== "win32") {
      throw new Error(currentTranslations.errors.windowsOnly);
    }

    createTray();
    void refreshDisplayCache().catch((error: unknown) => {
      console.error(
        currentTranslations.errors.startupDisplayLoadFailed,
        getErrorMessage(error),
      );
    });
  })
  .catch((error: unknown) => {
    dialog.showErrorBox(
      currentTranslations.errors.startupFailed,
      getErrorMessage(error),
    );
    app.quit();
  });
