export type TranslationMessages = {
  menu: {
    currentMode: string;
    currentMarker: string;
    primaryMarker: string;
    resolutionLabel: string;
    refreshRateLabel: string;
    displayLabel: string;
    refreshDisplays: string;
    quit: string;
    displayQueryFailed: string;
    unknownError: string;
    retry: string;
  };
  errors: {
    invalidResolutionData: string;
    incompleteResolutionData: string;
    invalidDisplayData: string;
    incompleteDisplayData: string;
    unavailableCurrentMode: string;
    invalidDisplayList: string;
    noActiveDisplays: string;
    emptyDisplayOutput: string;
    changeDisplayModeFailed: string;
    trayIconLoadFailed: string;
    windowsOnly: string;
    startupDisplayLoadFailed: string;
    startupFailed: string;
  };
};
