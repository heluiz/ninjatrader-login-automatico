#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$temporary = $null
$secret = $null
$restored = $null
$code = 0
try {
    if ($env:OS -ne 'Windows_NT') { throw 'Execute no Windows.' }
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot 'NinjaAutoLogin.ps1'), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -ne 0) { throw 'Falha na sintaxe do script PowerShell.' }
    Write-Host '[OK] Sintaxe do PowerShell.'
    Add-Type -AssemblyName @('UIAutomationClient', 'UIAutomationTypes', 'WindowsBase')
    $references = @(
        'System.dll',
        'System.Core.dll',
        [Windows.Automation.AutomationElement].Assembly.Location,
        [Windows.Automation.AutomationPattern].Assembly.Location,
        [Windows.Threading.Dispatcher].Assembly.Location
    )
    Add-Type -Path (Join-Path $PSScriptRoot 'NinjaUi.cs') -ReferencedAssemblies $references
    Write-Host '[OK] Compilacao do auxiliar de acessibilidade.'
    $inputType = [NinjaAutoLogin.Ui].GetNestedType('Input', [Reflection.BindingFlags]::NonPublic)
    $expectedSize = if ([IntPtr]::Size -eq 8) { 40 } else { 28 }
    if ([Runtime.InteropServices.Marshal]::SizeOf($inputType) -ne $expectedSize) {
        throw 'Tamanho da estrutura SendInput incorreto para esta arquitetura.'
    }
    Write-Host '[OK] Estrutura nativa de teclado para esta arquitetura.'
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('ninja-test-' + [guid]::NewGuid().ToString('N') + '.clixml')
    $sample = 'Ninja-Dummy-Test-Only!2026'
    $secret = ConvertTo-SecureString $sample -AsPlainText -Force
    [PSCredential]::new('dummy-test', $secret) | Export-Clixml -LiteralPath $temporary
    if ([IO.File]::ReadAllText($temporary).Contains($sample)) { throw 'A senha ficticia apareceu em texto legivel.' }
    $restored = Import-Clixml -LiteralPath $temporary
    if ($restored.GetNetworkCredential().Password -cne $sample) { throw 'Falha na recarga da credencial ficticia.' }
    Write-Host '[OK] Gravacao e recarga de uma senha FICTICIA protegida por Windows DPAPI.'
    Write-Host ''
    Write-Host 'Validacao local concluida. O proximo teste e reconhecer a janela real com DIAGNOSTICAR.cmd.' -ForegroundColor Green
    Write-Host 'Nenhuma credencial real foi lida; o NinjaTrader nao foi aberto ou controlado por este teste.'
}
catch { Write-Host ('Falha: ' + $_.Exception.Message) -ForegroundColor Red; $code = 1 }
finally {
    if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Force }
    if ($null -ne $secret) { $secret.Dispose() }
    if ($null -ne $restored) { $restored.Password.Dispose() }
    Read-Host 'Pressione Enter para fechar' | Out-Null
}
exit $code
