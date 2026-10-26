# Desktop Frame Rate App

Aplicativo Electron para Windows que fica somente na bandeja do sistema. Clique
com o botão direito no ícone para ver as taxas de atualização disponíveis para
o monitor principal; a taxa atual aparece marcada. Ao selecionar outra taxa, o
aplicativo a aplica sem alterar a resolução ou a profundidade de cor.

A lista é consultada ao abrir o menu e contém os modos disponíveis para a
resolução e profundidade de cor atuais do monitor principal.

## Desenvolvimento

Requisitos: Windows, Node.js e npm.

```powershell
npm install
npm start
```

Para gerar um instalador Windows:

```powershell
npm run package
```

O instalador NSIS fica na pasta `release`.
