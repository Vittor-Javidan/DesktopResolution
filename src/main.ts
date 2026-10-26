import { execFile } from "node:child_process";
import path from "node:path";
import { promisify } from "node:util";
import {
  app,
  dialog,
  Menu,
  nativeImage,
  Tray,
  type MenuItemConstructorOptions,
} from "electron";

type DisplayInfo = {
  displayName: string;
  width: number;
  height: number;
  currentHz: number;
  availableHz: number[];
};

const executeFile = promisify(execFile);
let tray: Tray | undefined;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

function isRefreshRate(value: unknown): value is number {
  return (
    isPositiveInteger(value) &&
    value >= 2 &&
    value <= 1000
  );
}

function parseDisplayInfo(value: unknown): DisplayInfo {
  if (!isRecord(value)) {
    throw new Error("O Windows retornou dados inválidos do monitor.");
  }

  const { displayName, width, height, currentHz, availableHz } = value;
  if (
    typeof displayName !== "string" ||
    !displayName ||
    !isPositiveInteger(width) ||
    !isPositiveInteger(height) ||
    !isRefreshRate(currentHz) ||
    !Array.isArray(availableHz) ||
    !availableHz.every(isRefreshRate)
  ) {
    throw new Error("O Windows retornou dados incompletos do monitor.");
  }

  const sortedRates = Array.from(new Set(availableHz)).sort(
    (left, right) => left - right,
  );
  if (!sortedRates.includes(currentHz)) {
    throw new Error("A taxa atual não consta entre os modos disponíveis.");
  }

  return {
    displayName,
    width,
    height,
    currentHz,
    availableHz: sortedRates,
  };
}

function getResourcePath(fileName: string): string {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, fileName);
  }

  return path.join(app.getAppPath(), "resources", fileName);
}

async function executeDisplayAction(
  action: "list" | "set",
  refreshRate?: number,
): Promise<DisplayInfo> {
  const args = [
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    getResourcePath("display-refresh.ps1"),
    "-Action",
    action,
  ];

  if (refreshRate !== undefined) {
    args.push("-RefreshRate", String(refreshRate));
  }

  const { stdout } = await executeFile("powershell.exe", args, {
    encoding: "utf8",
    windowsHide: true,
    timeout: 15_000,
    maxBuffer: 1_048_576,
  });
  const output = stdout.trim();
  if (!output) {
    throw new Error("O utilitário do Windows não retornou dados do monitor.");
  }

  return parseDisplayInfo(JSON.parse(output) as unknown);
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

function createRefreshMenu(display: DisplayInfo): Menu {
  const rateItems = display.availableHz.map(
    (rate): MenuItemConstructorOptions => ({
      label: `${rate} Hz${rate === display.currentHz ? " (atual)" : ""}`,
      type: "radio",
      checked: rate === display.currentHz,
      click: () => {
        if (rate !== display.currentHz) {
          void changeRefreshRate(rate);
        }
      },
    }),
  );

  return Menu.buildFromTemplate([
    {
      label: `Monitor principal: ${display.displayName}`,
      enabled: false,
    },
    {
      label: `${display.width} x ${display.height}`,
      enabled: false,
    },
    { type: "separator" },
    ...rateItems,
    { type: "separator" },
    {
      label: "Atualizar lista",
      click: () => {
        void openRefreshMenu();
      },
    },
    { label: "Sair", role: "quit" },
  ]);
}

function createErrorMenu(error: unknown): Menu {
  const details = getErrorMessage(error).replace(/\s+/g, " ").slice(0, 160);

  return Menu.buildFromTemplate([
    { label: "Falha ao consultar o monitor principal", enabled: false },
    { label: details || "Erro desconhecido.", enabled: false },
    { type: "separator" },
    {
      label: "Tentar novamente",
      click: () => {
        void openRefreshMenu();
      },
    },
    { label: "Sair", role: "quit" },
  ]);
}

async function openRefreshMenu(): Promise<void> {
  const currentTray = tray;
  if (!currentTray) {
    return;
  }

  try {
    const display = await executeDisplayAction("list");
    currentTray.setToolTip(
      `${display.currentHz} Hz - ${display.width} x ${display.height}`,
    );
    currentTray.popUpContextMenu(createRefreshMenu(display));
  } catch (error) {
    currentTray.popUpContextMenu(createErrorMenu(error));
  }
}

async function changeRefreshRate(refreshRate: number): Promise<void> {
  try {
    const display = await executeDisplayAction("set", refreshRate);
    tray?.setToolTip(
      `${display.currentHz} Hz - ${display.width} x ${display.height}`,
    );
  } catch (error) {
    dialog.showErrorBox(
      "Não foi possível alterar a taxa de atualização",
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
  tray.on("right-click", () => {
    void openRefreshMenu();
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
