import type { TranslationMessages } from "./types.js";

export const ptBr = {
  menu: {
    currentMode: "Atual: {mode}",
    currentMarker: " (atual)",
    primaryMarker: " - principal",
    resolutionLabel: "{width} x {height}{current}",
    refreshRateLabel: "{rate} Hz{current}",
    displayLabel: "{name}{primary}",
    refreshDisplays: "Atualizar monitores",
    quit: "Sair",
    displayQueryFailed: "Falha ao consultar os monitores",
    unknownError: "Erro desconhecido.",
    retry: "Tentar novamente",
  },
  errors: {
    invalidResolutionData: "O Windows retornou dados inválidos de resolução.",
    incompleteResolutionData:
      "O Windows retornou dados incompletos de resolução.",
    invalidDisplayData: "O Windows retornou dados inválidos do monitor.",
    incompleteDisplayData: "O Windows retornou dados incompletos do monitor.",
    unavailableCurrentMode:
      "O modo atual não consta entre as opções disponíveis.",
    invalidDisplayList: "O Windows retornou uma lista de monitores inválida.",
    noActiveDisplays: "Nenhum monitor ativo foi encontrado.",
    emptyDisplayOutput:
      "O utilitário do Windows não retornou dados dos monitores.",
    changeDisplayModeFailed: "Não foi possível alterar o modo do monitor",
    trayIconLoadFailed: "Não foi possível carregar o ícone da bandeja: {path}",
    windowsOnly: "Este aplicativo está disponível somente no Windows.",
    startupDisplayLoadFailed:
      "Falha ao carregar as opções dos monitores na inicialização:",
    startupFailed: "Falha ao iniciar o DesktopResolution",
  },
} as const satisfies TranslationMessages;
