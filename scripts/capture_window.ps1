param([Parameter(Mandatory=$true)][int]$ProcessId,
 [Parameter(Mandatory=$true)][string]$Output, [int]$Width=1460, [int]$Height=1160)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class TranslationWindowCapture {
 public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr arg);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc proc,IntPtr arg);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint processId);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd,System.Text.StringBuilder name,int size);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 public static IntPtr Find(int pid) { IntPtr found=IntPtr.Zero; EnumWindows((h,a)=> { uint id; GetWindowThreadProcessId(h,out id); var cls=new System.Text.StringBuilder(256); GetClassName(h,cls,256); if(id==pid && cls.ToString()=="FLUTTER_RUNNER_WIN32_WINDOW") { found=h; return false; } return true; }, IntPtr.Zero); return found; }
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd,out RECT rect);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd,int command);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
 [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hwnd,int x,int y,int width,int height,bool repaint);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
'@
[TranslationWindowCapture]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
$process = Get-Process -Id $ProcessId
$handle = [TranslationWindowCapture]::Find($ProcessId)
if ($handle -eq 0) { throw 'App has no visible window' }
[TranslationWindowCapture]::ShowWindow($handle,9) | Out-Null
[TranslationWindowCapture]::MoveWindow($handle,50,50,$Width,$Height,$true) | Out-Null
[TranslationWindowCapture]::SetForegroundWindow($handle) | Out-Null
[TranslationWindowCapture]::SetWindowPos($handle,[IntPtr](-1),0,0,0,0,3) | Out-Null
Start-Sleep -Milliseconds 700
$rect = New-Object TranslationWindowCapture+RECT
[TranslationWindowCapture]::GetWindowRect($handle,[ref]$rect) | Out-Null
$bitmap = New-Object Drawing.Bitmap ($rect.Right-$rect.Left),($rect.Bottom-$rect.Top)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($rect.Left,$rect.Top,0,0,$bitmap.Size)
$bitmap.Save($Output,[Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $bitmap.Dispose()
[TranslationWindowCapture]::SetWindowPos($handle,[IntPtr](-2),0,0,0,0,3) | Out-Null
