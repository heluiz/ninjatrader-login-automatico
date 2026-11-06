#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Configure,
    [switch]$Diagnose,
    [switch]$Remove,
    [string]$BitwardenItemId,
    [string]$NinjaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:InstallDir = Join-Path $env:LOCALAPPDATA 'Heluiz-NinjaAutoLogin'
$script:ConfigFile = Join-Path $script:InstallDir 'config.json'
$script:CredentialFile = Join-Path $script:InstallDir 'login.clixml'
$script:Shortcut = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'NinjaTrader - Login automatico.lnk'

function Set-PrivateDirectory {
    New-Item -Path $script:InstallDir -ItemType Directory -Force | Out-Null
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($identity)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($identity, $system)) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $script:InstallDir -AclObject $acl
}

function Resolve-NinjaPath {
    param([string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $base) { continue }
            foreach ($relative in @('NinjaTrader 8\bin\NinjaTrader.exe', 'NinjaTrader 8\bin64\NinjaTrader.exe')) {
                $path = Join-Path $base $relative
                if (Test-Path -LiteralPath $path -PathType Leaf) { $Candidate = $path; break }
            }
            if ($Candidate) { break }
        }
    }
    if (-not $Candidate) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = [Windows.Forms.OpenFileDialog]::new()
        try {
            $dialog.Title = 'Selecione o NinjaTrader.exe instalado no computador'
            $dialog.Filter = 'NinjaTrader.exe|NinjaTrader.exe'
            if ($dialog.ShowDialog() -ne 'OK') { throw 'Configuracao cancelada.' }
            $Candidate = $dialog.FileName
        }
        finally { $dialog.Dispose() }
    }
    $file = Get-Item -LiteralPath $Candidate
    if ($file.PSIsContainer -or $file.Name -ine 'NinjaTrader.exe') {
        throw 'Selecione o executavel NinjaTrader.exe da instalacao oficial.'
    }
    return $file.FullName
}

function Get-BitwardenCredential {
    param([string]$ItemId)
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($ItemId, [ref]$parsed)) { throw 'Informe o ID completo do item do Bitwarden (UUID).' }
    $bw = Get-Command bw -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $bw) { throw 'Bitwarden CLI (bw) nao encontrado. Consulte LEIA-ME.txt ou configure manualmente.' }
    if (-not $env:BW_SESSION) { throw 'Desbloqueie o Bitwarden CLI nessa sessao antes de importar. Consulte LEIA-ME.txt.' }
    Write-Host 'Importando apenas o item escolhido do Bitwarden...'
    $json = $null
    $item = $null
    try {
        $json = & $bw.Source get item $ItemId 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel ler o item. Verifique o ID e a sessao do Bitwarden CLI.' }
        try { $item = ($json -join "`n") | ConvertFrom-Json }
        catch { throw 'O Bitwarden CLI retornou um item em formato inesperado.' }
        if ($item.type -ne 1 -or -not $item.login.username -or -not $item.login.password) {
            throw 'O item selecionado precisa ser um Login com usuario e senha preenchidos.'
        }
        $secret = ConvertTo-SecureString -String $item.login.password -AsPlainText -Force
        return [PSCredential]::new([string]$item.login.username, $secret)
    }
    finally { $json = $null; $item = $null }
}

function Install-Launcher {
    $resolvedPath = Resolve-NinjaPath $NinjaPath
    $credential = $null
    try {
        if ($BitwardenItemId) { $credential = Get-BitwardenCredential $BitwardenItemId }
        else {
            $credential = Get-Credential -Message 'Informe o login INICIAL do NinjaTrader. Voce pode copiar do Bitwarden.'
        }
        if ($null -eq $credential -or -not $credential.UserName -or $credential.Password.Length -eq 0) {
            throw 'Configuracao cancelada: usuario e senha sao obrigatorios.'
        }
        Set-PrivateDirectory
        foreach ($name in @('NinjaAutoLogin.ps1', 'NinjaUi.cs')) {
            $source = Join-Path $PSScriptRoot $name
            $destination = Join-Path $script:InstallDir $name
            if ([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($destination)) {
                Copy-Item -LiteralPath $source -Destination $destination -Force
            }
        }
        # Windows DPAPI: the password is tied to this Windows user on this PC.
        $credential | Export-Clixml -LiteralPath $script:CredentialFile -Encoding UTF8
        [ordered]@{ Version = 1; NinjaPath = $resolvedPath; TimeoutSeconds = 60 } |
            ConvertTo-Json | Set-Content -LiteralPath $script:ConfigFile -Encoding UTF8
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $launcher = Join-Path $script:InstallDir 'NinjaAutoLogin.ps1'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($script:Shortcut)
        $shortcut.TargetPath = $powershell
        $shortcut.Arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "' + $launcher + '"'
        $shortcut.WorkingDirectory = $script:InstallDir
        $shortcut.Description = 'Abre o NinjaTrader e preenche o login inicial.'
        $shortcut.IconLocation = $resolvedPath + ',0'
        $shortcut.Save()
        Write-Host ''
        Write-Host 'Configurado. Use o atalho NinjaTrader - Login automatico na Area de Trabalho.' -ForegroundColor Green
        Write-Host 'A senha foi protegida pelo Windows. Este script nao salva a senha mestra do Bitwarden.'
    }
    finally { if ($null -ne $credential) { $credential.Password.Dispose() }; $credential = $null }
}

function Start-NinjaLogin {
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) {
        throw 'Execute CONFIGURAR.cmd primeiro.'
    }
    $config = Get-Content -LiteralPath $script:ConfigFile -Raw | ConvertFrom-Json
    $resolvedPath = Resolve-NinjaPath $config.NinjaPath
    Add-Type -AssemblyName @('UIAutomationClient', 'UIAutomationTypes', 'WindowsBase')
    $references = @(
        'System.dll',
        'System.Core.dll',
        [Windows.Automation.AutomationElement].Assembly.Location,
        [Windows.Automation.AutomationPattern].Assembly.Location,
        [Windows.Threading.Dispatcher].Assembly.Location
    )
    Add-Type -Path (Join-Path $PSScriptRoot 'NinjaUi.cs') -ReferencedAssemblies $references
    if ($Diagnose) {
        $form = [NinjaAutoLogin.Ui]::Find($resolvedPath)
        if ($null -eq $form) {
            Write-Host 'Login nao identificado. Deixe a janela inicial do NinjaTrader aberta e tente novamente.'
            Write-Host 'Se continuar, os seletores de acessibilidade precisam de ajuste para sua versao.'
        }
        else {
            Write-Host 'Janela, campo de usuario, campo de senha e botao Entrar identificados.' -ForegroundColor Green
            Write-Host 'Nenhuma credencial foi lida ou preenchida neste diagnostico.'
        }
        Read-Host 'Pressione Enter para fechar' | Out-Null
        return
    }
    $running = @(Get-Process -Name NinjaTrader -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -ieq $resolvedPath } catch { $false }
    })
    if ($running.Count -eq 0) {
        Start-Process -FilePath $resolvedPath -WorkingDirectory (Split-Path $resolvedPath)
    }
    Write-Host 'Aguardando o login do NinjaTrader. Aguarde sem trocar de janela...'
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(120, [Math]::Max(10, [int]$config.TimeoutSeconds)))
    $form = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $form = [NinjaAutoLogin.Ui]::Find($resolvedPath)
        if ($null -ne $form) { break }
        Start-Sleep -Milliseconds 400
    }
    if ($null -eq $form) {
        throw 'Login nao identificado. O NinjaTrader pode ja estar aberto, ou sua versao exige ajustar os seletores. Use DIAGNOSTICAR.cmd com a tela de login aberta.'
    }
    $credential = $null
    try {
        # Decrypt only once the expected application and its login controls are found.
        $credential = Import-Clixml -LiteralPath $script:CredentialFile
        if ($credential -isnot [PSCredential]) { throw 'Credencial invalida. Execute CONFIGURAR.cmd novamente.' }
        [NinjaAutoLogin.Ui]::FillAndSubmit($form, $credential.UserName, $credential.Password)
        Write-Host 'Login enviado uma vez. Confira o resultado na janela do NinjaTrader.' -ForegroundColor Green
    }
    finally { if ($credential -is [PSCredential]) { $credential.Password.Dispose() }; $credential = $null }
}

$mutex = $null
$ownsMutex = $false
$code = 0
try {
    if ($env:OS -ne 'Windows_NT') { throw 'Este inicializador funciona somente no Windows.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Use os arquivos .cmd ou o atalho para executar em modo STA.' }
    if (@($Configure, $Diagnose, $Remove).Where({ $_.IsPresent }).Count -gt 1) {
        throw 'Escolha apenas uma acao: Configure, Diagnose ou Remove.'
    }
    if (($BitwardenItemId -or $NinjaPath) -and -not $Configure) { throw 'BitwardenItemId e NinjaPath so podem ser usados com -Configure.' }
    $mutex = [Threading.Mutex]::new($false, 'Local\HeluizNinjaAutoLogin')
    try { $ownsMutex = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { throw 'O inicializador ja esta em execucao. Aguarde a outra janela.' }
    if ($Configure) { Install-Launcher }
    elseif ($Remove) {
        if (Test-Path -LiteralPath $script:Shortcut) { Remove-Item -LiteralPath $script:Shortcut -Force }
        if (Test-Path -LiteralPath $script:InstallDir) { Remove-Item -LiteralPath $script:InstallDir -Recurse -Force }
        Write-Host 'Inicializador e credencial local removidos. O NinjaTrader e o Bitwarden foram preservados.'
    }
    else { Start-NinjaLogin }
}
catch {
    Write-Host ('Nao foi possivel concluir: ' + $_.Exception.Message) -ForegroundColor Red
    $code = 1
    Read-Host 'Pressione Enter para fechar' | Out-Null
}
finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
exit $code
