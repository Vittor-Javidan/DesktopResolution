import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
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
    throw new Error("O Windows retornou dados inválidos de resolução.");
  }

  const { width, height, availableRefreshRates } = value;
  if (
    !isPositiveInteger(width) ||
    !isPositiveInteger(height) ||
    !Array.isArray(availableRefreshRates) ||
    availableRefreshRates.length === 0 ||
    !availableRefreshRates.every(isRefreshRate)
  ) {
    throw new Error("O Windows retornou dados incompletos de resolução.");
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
    throw new Error("O Windows retornou dados inválidos do monitor.");
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
    throw new Error("O Windows retornou dados incompletos do monitor.");
  }

  const parsedResolutions = availableResolutions.map(parseResolutionInfo);
  const currentResolution = parsedResolutions.find(
    (resolution) =>
      resolution.width === currentWidth && resolution.height === currentHeight,
  );
  if (
    !currentResolution?.availableRefreshRates.includes(currentRefreshRate)
  ) {
    throw new Error("O modo atual não consta entre as opções disponíveis.");
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
    throw new Error("O Windows retornou uma lista de monitores inválida.");
  }
  if (value.displays.length === 0) {
    throw new Error("Nenhum monitor ativo foi encontrado.");
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
    throw new Error("O utilitário do Windows não retornou dados dos monitores.");
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
      : "Desktop Frame Rate App",
  );
}

function createDisplayMenuItem(display: DisplayInfo): MenuItemConstructorOptions {
  const resolutionItems = display.availableResolutions.map(
    (resolution): MenuItemConstructorOptions => {
      const isCurrentResolution =
        resolution.width === display.currentWidth &&
        resolution.height === display.currentHeight;

      return {
        label: `${resolution.width} x ${resolution.height}${isCurrentResolution ? " (atual)" : ""}`,
        submenu: resolution.availableRefreshRates.map(
          (rate): MenuItemConstructorOptions => {
            const isCurrentMode =
              isCurrentResolution && rate === display.currentRefreshRate;

            return {
              label: `${rate} Hz${isCurrentMode ? " (atual)" : ""}`,
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
    label: `${display.displayName}${display.isPrimary ? " - principal" : ""}`,
    submenu: [
      {
        label: `Atual: ${formatCurrentMode(display)}`,
        enabled: false,
      },
      { type: "separator" },
      ...resolutionItems,
    ],
  };
}

function createDisplayMenu(displays: DisplayInfo[]): Menu {
  return Menu.buildFromTemplate([
    ...displays.map(createDisplayMenuItem),
    { type: "separator" },
    {
      label: "Atualizar monitores",
      click: () => {
        void openDisplayMenu();
      },
    },
    { label: "Sair", role: "quit" },
  ]);
}

function createErrorMenu(error: unknown): Menu {
  const details = getErrorMessage(error).replace(/\s+/g, " ").slice(0, 160);

  return Menu.buildFromTemplate([
    { label: "Falha ao consultar os monitores", enabled: false },
    { label: details || "Erro desconhecido.", enabled: false },
    { type: "separator" },
    {
      label: "Tentar novamente",
      click: () => {
        void openDisplayMenu();
      },
    },
    { label: "Sair", role: "quit" },
  ]);
}

async function openDisplayMenu(): Promise<void> {
  const currentTray = tray;
  if (!currentTray || isLoadingMenu) {
    return;
  }

  isLoadingMenu = true;
  try {
    const displays = await executeDisplayAction({ type: "list" });
    updateTrayToolTip(displays);
    currentTray.popUpContextMenu(createDisplayMenu(displays));
  } catch (error) {
    currentTray.popUpContextMenu(createErrorMenu(error));
  } finally {
    isLoadingMenu = false;
  }
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
    updateTrayToolTip(displays);
  } catch (error) {
    dialog.showErrorBox(
      "Não foi possível alterar o modo do monitor",
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
    throw new Error(`Não foi possível carregar o ícone da bandeja: ${iconPath}`);
  }

  tray = new Tray(icon);
  tray.setToolTip("Desktop Frame Rate App");
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
    if (process.platform !== "win32") {
      throw new Error("Este aplicativo está disponível somente no Windows.");
    }

    createTray();
  })
  .catch((error: unknown) => {
    dialog.showErrorBox(
      "Falha ao iniciar o Desktop Frame Rate App",
      getErrorMessage(error),
    );
    app.quit();
  });
