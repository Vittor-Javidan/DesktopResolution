# Desktop Frame Rate App

Aplicativo Electron para Windows com um ícone na bandeja do sistema. O menu do
ícone contém somente a opção **Sair**.

Clique com o botão direito na área de trabalho e passe o mouse sobre **Refresh
Rate** para abrir a lista de taxas disponíveis. Em configurações com vários
monitores, a lista e a alteração correspondem ao monitor sob o ponteiro no
momento do clique. A taxa atual aparece marcada; selecionar outra taxa mantém a
resolução e a profundidade de cor atuais.

O instalador registra o menu para o usuário atual e o remove ao desinstalar.

## Desenvolvimento

Requisitos: Windows 64 bits, Node.js, npm e .NET Framework 4.x.

```powershell
npm install
npm run build
npm run register:context-menu
npm start
```

Para remover o menu de contexto durante o desenvolvimento:

```powershell
npm run unregister:context-menu
```

Para gerar um instalador Windows:

```powershell
npm run package
```

O instalador NSIS fica na pasta `release`. Se o Windows mantiver o menu antigo
em cache após instalar ou desinstalar, reinicie o Explorador de Arquivos.
