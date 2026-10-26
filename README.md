# DesktopResolution

Aplicativo Electron para Windows que fica na bandeja do sistema. Clique com o
botão esquerdo ou direito no ícone para abrir a lista de monitores conectados.
Os monitores aparecem como **Display 1**, **Display 2** etc.; o monitor principal
é identificado com **- principal**. Cada monitor mostra apenas os modos de
resolução e taxa que o Windows confirma como compatíveis. A resolução e a taxa
atuais aparecem marcadas.

Ao selecionar uma taxa, o aplicativo aplica a combinação de resolução e taxa
somente ao monitor escolhido, preservando a profundidade de cor atual e
revalidando o modo antes de aplicá-lo. As opções são consultadas novamente
ao iniciar o aplicativo e ficam em cache para abrir o menu imediatamente. Use
**Atualizar monitores** para consultar as opções novamente; após uma troca de
modo, o cache é atualizado automaticamente.

O instalador remove registros do antigo menu de contexto durante a atualização
e ao desinstalar, configura o aplicativo para iniciar automaticamente com o
Windows e remove essa configuração ao desinstalar.

## Desenvolvimento

Requisitos: Windows 64 bits, Node.js e npm.

```powershell
npm install
npm run build
npm start
```

Para remover registros do menu de contexto de uma instalação anterior:

```powershell
npm run unregister:context-menu
```

Para gerar um instalador Windows:

```powershell
npm run package
```

O instalador NSIS fica na pasta `release`.
