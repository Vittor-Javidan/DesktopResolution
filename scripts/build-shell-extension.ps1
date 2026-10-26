$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$output = Join-Path $root "resources\RefreshRateShellExtension.dll"
$sources = @(
    (Join-Path $root "src\shell\DisplayApi.cs"),
    (Join-Path $root "src\shell\ContextMenuHandler.cs"),
    (Join-Path $root "src\shell\ExplorerCommand.cs")
)

if (-not (Test-Path $compiler)) {
    throw "O compilador C# do .NET Framework 4.x não foi encontrado: $compiler"
}

foreach ($source in $sources) {
    if (-not (Test-Path $source)) {
        throw "Arquivo-fonte da extensão do Explorer não encontrado: $source"
    }
}

$arguments = @(
    "/nologo",
    "/target:library",
    "/platform:x64",
    "/optimize+",
    "/out:$output"
) + $sources

& $compiler @arguments
if ($LASTEXITCODE -ne 0) {
    throw "A compilação da extensão do menu de contexto falhou com código $LASTEXITCODE."
}

Write-Output "Extensão do Explorer compilada: $output"
