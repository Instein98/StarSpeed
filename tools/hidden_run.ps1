param(
    [Parameter(Mandatory = $true)][string]$CommandLine,
    [int]$TimeoutSec = 90
)
# 在一个单独的、不显示的 Windows 桌面上启动进程：窗口照常创建和渲染，但不会出现在用户的屏幕上，也不会抢焦点。

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class HiddenDesktop {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateDesktopW(string name, IntPtr device, IntPtr devmode, int flags, uint access, IntPtr sa);
    [DllImport("user32.dll")]
    public static extern bool CloseDesktop(IntPtr h);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit,
        uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] public static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
"@

$name = "ClaudeGodotHidden"
$desk = [HiddenDesktop]::CreateDesktopW($name, [IntPtr]::Zero, [IntPtr]::Zero, 0, 0x10000000, [IntPtr]::Zero)
if ($desk -eq [IntPtr]::Zero) { Write-Output "CreateDesktop failed"; exit 2 }
$si = New-Object HiddenDesktop+STARTUPINFO
$si.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($si)
$si.lpDesktop = $name
$pi = New-Object HiddenDesktop+PROCESS_INFORMATION
$cmd = New-Object System.Text.StringBuilder($CommandLine, 32768)
$ok = [HiddenDesktop]::CreateProcessW([NullString]::Value, $cmd, [IntPtr]::Zero, [IntPtr]::Zero, $false, 0, [IntPtr]::Zero, [NullString]::Value, [ref]$si, [ref]$pi)
if (-not $ok) { Write-Output ("CreateProcess failed, win32 error " + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()); [void][HiddenDesktop]::CloseDesktop($desk); exit 3 }
$wait = [HiddenDesktop]::WaitForSingleObject($pi.hProcess, [uint32]($TimeoutSec * 1000))
if ($wait -ne 0) {
    [void][HiddenDesktop]::TerminateProcess($pi.hProcess, 1)
    Write-Output "timeout: process terminated"
}
$code = 0
[void][HiddenDesktop]::GetExitCodeProcess($pi.hProcess, [ref]$code)
[void][HiddenDesktop]::CloseHandle($pi.hThread)
[void][HiddenDesktop]::CloseHandle($pi.hProcess)
[void][HiddenDesktop]::CloseDesktop($desk)
Write-Output "exit code $code"


