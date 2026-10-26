!macro customInstall
  ExecWait '"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\resources\unregister-context-menu.ps1"' $0
  ${If} $0 != 0
    Abort "Não foi possível remover os registros do antigo menu de contexto."
  ${EndIf}

  ClearErrors
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "Desktop Frame Rate App" '"$INSTDIR\${APP_EXECUTABLE_FILENAME}"'
  IfErrors 0 +2
  Abort "Não foi possível configurar a inicialização automática."
!macroend

!macro customUnInstall
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "Desktop Frame Rate App"
  ExecWait '"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\resources\unregister-context-menu.ps1"' $0
  ${If} $0 != 0
    MessageBox MB_ICONEXCLAMATION "Não foi possível remover automaticamente os registros do antigo menu de contexto."
  ${EndIf}
!macroend
