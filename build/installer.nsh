!macro customInstall
  ExecWait '"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\resources\register-context-menu.ps1" -AssemblyPath "$INSTDIR\resources\RefreshRateShellExtension.dll"' $0
  ${If} $0 != 0
    Abort "Não foi possível registrar o menu Refresh Rate no Explorer."
  ${EndIf}
!macroend

!macro customUnInstall
  ExecWait '"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\resources\unregister-context-menu.ps1"' $0
  ${If} $0 != 0
    MessageBox MB_ICONEXCLAMATION "Não foi possível remover automaticamente o menu Refresh Rate."
  ${EndIf}
!macroend
