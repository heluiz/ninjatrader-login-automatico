using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Automation;

namespace NinjaAutoLogin
{
    public sealed class LoginForm
    {
        public AutomationElement Window;
        public AutomationElement Username;
        public AutomationElement Password;
        public AutomationElement Submit;
        public string ExePath;
        public int ProcessId;
    }

    public static class Ui
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct MouseInput
        {
            public int X, Y;
            public uint Data, Flags, Time;
            public UIntPtr Extra;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct KeyInput
        {
            public ushort Key, Scan;
            public uint Flags, Time;
            public UIntPtr Extra;
        }
        [StructLayout(LayoutKind.Explicit)]
        private struct InputUnion
        {
            [FieldOffset(0)] public MouseInput Mouse;
            [FieldOffset(0)] public KeyInput Keyboard;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct Input
        {
            public uint Type;
            public InputUnion Data;
        }
        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint count, Input[] inputs, int size);
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr window);
        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr window, int command);
        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int key);

        private static bool Visible(AutomationElement item)
        {
            return !item.Current.IsOffscreen;
        }

        // Inspect control metadata only: never read field values or passwords.
        public static LoginForm Find(string exePath)
        {
            HashSet<int> ids = new HashSet<int>();
            foreach (Process process in Process.GetProcessesByName("NinjaTrader"))
            {
                using (process)
                {
                    try
                    {
                        if (String.Equals(process.MainModule.FileName, exePath,
                            StringComparison.OrdinalIgnoreCase)) ids.Add(process.Id);
                    }
                    catch (System.ComponentModel.Win32Exception) { }
                    catch (InvalidOperationException) { }
                }
            }
            List<LoginForm> matches = new List<LoginForm>();
            AutomationElementCollection windows = AutomationElement.RootElement.FindAll(
                TreeScope.Children, Condition.TrueCondition);
            foreach (AutomationElement window in windows)
            {
                try
                {
                    if (!ids.Contains(window.Current.ProcessId)) continue;
                    List<AutomationElement> users = new List<AutomationElement>();
                    List<AutomationElement> passwords = new List<AutomationElement>();
                    List<AutomationElement> buttons = new List<AutomationElement>();
                    Condition wanted = new OrCondition(
                        new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit),
                        new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button));
                    foreach (AutomationElement item in window.FindAll(TreeScope.Descendants, wanted))
                    {
                        if (!Visible(item)) continue;
                        if (item.Current.ControlType == ControlType.Edit)
                        {
                            if (!item.Current.IsEnabled) continue;
                            if (item.Current.IsPassword) passwords.Add(item);
                            else users.Add(item);
                        }
                        else
                        {
                            string name = item.Current.Name.Trim();
                            string id = item.Current.AutomationId;
                            if (Regex.IsMatch(name, @"^(log\s*in|sign\s*in|entrar|acessar|iniciar sess[aã]o)$", RegexOptions.IgnoreCase)
                                || Regex.IsMatch(id, @"^(btnLogin|loginButton|logInButton|signInButton)$", RegexOptions.IgnoreCase))
                                buttons.Add(item);
                        }
                    }
                    if (passwords.Count != 1 || buttons.Count != 1) continue;
                    if (users.Count > 1)
                    {
                        users = users.FindAll(delegate(AutomationElement item)
                        {
                            return Regex.IsMatch(item.Current.AutomationId + " " + item.Current.Name,
                                @"user|usu[aá]rio|email|e-mail", RegexOptions.IgnoreCase);
                        });
                    }
                    if (users.Count != 1) continue;
                    matches.Add(new LoginForm { Window = window, Username = users[0],
                        Password = passwords[0], Submit = buttons[0], ExePath = exePath,
                        ProcessId = window.Current.ProcessId });
                }
                catch (ElementNotAvailableException) { }
            }
            if (matches.Count > 1)
                throw new InvalidOperationException("Mais de uma janela de login encontrada. Feche as extras e tente novamente.");
            return matches.Count == 1 ? matches[0] : null;
        }

        private static void CheckProcess(LoginForm form)
        {
            using (Process process = Process.GetProcessById(form.ProcessId))
            {
                if (!String.Equals(process.MainModule.FileName, form.ExePath,
                    StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("O processo mudou. Preenchimento interrompido.");
            }
        }

        private static void CheckFocus(LoginForm form, AutomationElement field)
        {
            IntPtr window = new IntPtr(form.Window.Current.NativeWindowHandle);
            AutomationElement focused = AutomationElement.FocusedElement;
            if (window == IntPtr.Zero || GetForegroundWindow() != window
                || focused == null || !Automation.Compare(focused, field))
                throw new InvalidOperationException("O foco mudou. Preenchimento interrompido; execute o atalho novamente.");
        }

        private static Input Key(ushort key, ushort scan, uint flags)
        {
            return new Input { Type = 1, Data = new InputUnion {
                Keyboard = new KeyInput { Key = key, Scan = scan, Flags = flags } } };
        }

        private static void Send(Input[] inputs)
        {
            if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(Input))) != inputs.Length)
                throw new InvalidOperationException("Windows recusou a digitacao. Execute o NinjaTrader e o script com o mesmo nivel de permissao.");
        }

        private static void PrepareField(LoginForm form, AutomationElement field)
        {
            CheckProcess(form);
            IntPtr window = new IntPtr(form.Window.Current.NativeWindowHandle);
            if (IsIconic(window)) ShowWindow(window, 9);
            SetForegroundWindow(window);
            Thread.Sleep(150);
            field.SetFocus();
            Thread.Sleep(100);
            CheckFocus(form, field);
            // Do not combine the synthetic input with keys the user is holding.
            foreach (int key in new int[] { 0x10, 0x11, 0x12, 0x5B, 0x5C })
                if ((GetAsyncKeyState(key) & 0x8000) != 0)
                    throw new InvalidOperationException("Solte Shift, Ctrl, Alt e Windows e tente novamente.");
            Send(new Input[] { Key(0x11, 0, 0), Key(0x41, 0, 0),
                Key(0x41, 0, 2), Key(0x11, 0, 2) });
            CheckFocus(form, field);
            Send(new Input[] { Key(0x08, 0, 0), Key(0x08, 0, 2) });
        }

        private static void TypeChar(LoginForm form, AutomationElement field, char value)
        {
            CheckFocus(form, field);
            Send(new Input[] { Key(0, value, 4), Key(0, value, 6) });
            Thread.Sleep(10);
        }

        public static void FillAndSubmit(LoginForm form, string username, SecureString password)
        {
            if (String.IsNullOrWhiteSpace(username) || password == null || password.Length == 0)
                throw new InvalidOperationException("Credenciais vazias. Execute Configurar novamente.");
            PrepareField(form, form.Username);
            foreach (char value in username) TypeChar(form, form.Username, value);
            Thread.Sleep(150);
            PrepareField(form, form.Password);
            IntPtr buffer = IntPtr.Zero;
            try
            {
                buffer = Marshal.SecureStringToBSTR(password);
                for (int index = 0; index < password.Length; index++)
                    TypeChar(form, form.Password, (char)Marshal.ReadInt16(buffer, index * 2));
            }
            finally
            {
                if (buffer != IntPtr.Zero) Marshal.ZeroFreeBSTR(buffer);
            }
            Thread.Sleep(150);
            CheckProcess(form);
            CheckFocus(form, form.Password);
            // Login buttons may be disabled until both input fields are populated.
            for (int attempt = 0; attempt < 30 && !form.Submit.Current.IsEnabled; attempt++)
            {
                CheckFocus(form, form.Password);
                Thread.Sleep(100);
            }
            if (!form.Submit.Current.IsEnabled)
                throw new InvalidOperationException("Os campos foram preenchidos, mas o botao Entrar continua desabilitado. Confira a tela.");
            object pattern;
            if (!form.Submit.TryGetCurrentPattern(InvokePattern.Pattern, out pattern))
                throw new InvalidOperationException("Os campos foram preenchidos. Clique em Entrar no NinjaTrader.");
            ((InvokePattern)pattern).Invoke();
            // Exactly one attempt. No retries, connection changes, or trading commands.
        }
    }
}
