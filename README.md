# NinjaTrader — login automático

Abre o NinjaTrader 8 e preenche a tela inicial de login com o usuário e a senha guardados no próprio Windows. Versão 0.1.0, experimental, para Windows 10/11 com Windows PowerShell 5.1.

## Como usar

1. Baixe o repositório (**Code → Download ZIP**) e extraia todos os arquivos numa pasta.
2. Dê dois cliques em `CONFIGURAR.cmd`, com o seu usuário normal do Windows (sem Administrador).
3. Se pedir, selecione o `NinjaTrader.exe` e informe o usuário e a senha da tela inicial do NinjaTrader.
4. Use o atalho **NinjaTrader - Login automatico**, criado na Área de Trabalho. Durante o preenchimento, não use o teclado nem troque de janela.

O manual completo, com a importação opcional pelo Bitwarden e o diagnóstico, está em [LEIA-ME.txt](LEIA-ME.txt).

## Segurança

- A senha fica criptografada pelo Windows (DPAPI), vinculada ao seu usuário e ao computador, em `%LOCALAPPDATA%\Heluiz-NinjaAutoLogin`, com permissão só para o seu usuário e o SYSTEM. O nome de usuário fica legível nesse arquivo.
- Nada é enviado a terceiros: o login segue do próprio NinjaTrader para os servidores dele.
- Programas executados com o mesmo usuário do Windows conseguem ler essa senha; a criptografia local não protege uma conta do Windows comprometida.
- A senha não passa pela área de transferência, e o pacote não pede nem guarda a senha mestra do Bitwarden.

## Limites

O botão **Entrar** é acionado uma única vez. MFA, CAPTCHA ou termos precisam ser concluídos na própria tela. O pacote não mexe em conexões, contas, estratégias nem ordens. O que foi validado está em [VALIDACAO.txt](VALIDACAO.txt); use `VALIDAR-WINDOWS.cmd` e `DIAGNOSTICAR.cmd` para conferir no seu computador.

Para remover o atalho, o inicializador e a credencial, execute `REMOVER.cmd`.

## Licença

[MIT](LICENSE). Projeto independente, sem afiliação com a NinjaTrader.
