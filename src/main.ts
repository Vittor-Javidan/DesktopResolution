import path from "node:path";
import { app, dialog, Menu, nativeImage, Tray } from "electron";

let tray: Tray | undefined;

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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
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
  tray.setContextMenu(
    Menu.buildFromTemplate([{ label: "Sair", role: "quit" }]),
  );
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
