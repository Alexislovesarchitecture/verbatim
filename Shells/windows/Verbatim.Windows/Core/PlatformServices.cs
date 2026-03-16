using NAudio.Wave;
using System.Diagnostics;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text;
using Windows.ApplicationModel.DataTransfer;

namespace Verbatim.Windows.Core;

internal sealed class WindowsSystemProfileService
{
    internal SystemProfilePayload Current()
    {
        var version = Environment.OSVersion.Version;
        return new SystemProfilePayload
        {
            OsFamily = "windows",
            OsVersion = new SystemVersionPayload
            {
                Major = version.Major,
                Minor = version.Minor,
                Patch = version.Build,
            },
            Architecture = RuntimeInformation.ProcessArchitecture switch
            {
                Architecture.Arm64 => "arm64",
                _ => "x86_64",
            },
            Accelerator = DetectAccelerator(),
        };
    }

    private static string DetectAccelerator()
    {
        var candidates = new[]
        {
            "nvidia-smi.exe",
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                "NVIDIA Corporation",
                "NVSMI",
                "nvidia-smi.exe"),
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                "NVIDIA Corporation",
                "NVSMI",
                "nvidia-smi.exe"),
        };

        return candidates.Any(File.Exists) ? "nvidia_cuda" : "none";
    }
}

internal sealed class WindowsPermissionsManager
{
    internal PermissionStatus CheckMicrophone()
    {
        try
        {
            var count = WaveInEvent.DeviceCount;
            return count > 0
                ? new PermissionStatus(true, "Microphone capture is available.", null)
                : new PermissionStatus(false, "No microphone capture device is currently available.", "ms-settings:privacy-microphone");
        }
        catch (Exception error)
        {
            return new PermissionStatus(false, error.Message, "ms-settings:privacy-microphone");
        }
    }
}

internal sealed record PermissionStatus(bool IsGranted, string Message, string? ActionUri);

internal sealed class WindowsFocusContextService
{
    internal ActiveContextSnapshot Capture()
    {
        var foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero)
        {
            return new ActiveContextSnapshot("Unknown app", null, null, null, null, null, "No active window detected.");
        }

        _ = GetWindowThreadProcessId(foreground, out var processId);
        string? processName = null;
        try
        {
            processName = Process.GetProcessById((int)processId).ProcessName;
        }
        catch
        {
        }

        var windowTitle = ReadWindowText(foreground);
        IntPtr focusHandle = IntPtr.Zero;
        var thread = GetWindowThreadProcessId(foreground, out _);
        GUITHREADINFO info = new() { cbSize = Marshal.SizeOf<GUITHREADINFO>() };
        if (GetGUIThreadInfo(thread, ref info))
        {
            focusHandle = info.hwndFocus;
        }

        string? controlClass = focusHandle != IntPtr.Zero ? ReadWindowClass(focusHandle) : null;
        string? controlTitle = focusHandle != IntPtr.Zero ? ReadWindowText(focusHandle) : null;

        return new ActiveContextSnapshot(
            processName ?? "Foreground app",
            processName,
            windowTitle,
            controlClass,
            controlTitle,
            focusHandle == IntPtr.Zero ? null : focusHandle.ToString(),
            focusHandle == IntPtr.Zero ? "Focused control metadata is unavailable." : null);
    }

    private static string? ReadWindowText(IntPtr handle)
    {
        var builder = new StringBuilder(512);
        var length = GetWindowText(handle, builder, builder.Capacity);
        return length > 0 ? builder.ToString() : null;
    }

    private static string? ReadWindowClass(IntPtr handle)
    {
        var builder = new StringBuilder(256);
        var length = GetClassName(handle, builder, builder.Capacity);
        return length > 0 ? builder.ToString() : null;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GUITHREADINFO
    {
        public int cbSize;
        public int flags;
        public IntPtr hwndActive;
        public IntPtr hwndFocus;
        public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner;
        public IntPtr hwndMoveSize;
        public IntPtr hwndCaret;
        public RECT rcCaret;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll")]
    private static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO lpgui);
}

internal sealed record ActiveContextSnapshot(
    string AppName,
    string? ProcessName,
    string? WindowTitle,
    string? FocusedControlClass,
    string? FocusedControlTitle,
    string? FocusedHandle,
    string? Note);

internal sealed class WindowsPasteService
{
    internal async Task<PasteOperationResult> CopyAsync(string text)
    {
        try
        {
            var package = new DataPackage();
            package.SetText(text);
            Clipboard.SetContent(package);
            Clipboard.Flush();
            await Task.CompletedTask;
            return new PasteOperationResult("clipboard_only", "Copied to the Windows clipboard.");
        }
        catch (Exception error)
        {
            return new PasteOperationResult("failed", error.Message);
        }
    }
}

internal sealed record PasteOperationResult(string Mode, string Message);

internal sealed class WindowsRecordingManager
{
    private WaveInEvent? capture;
    private WaveFileWriter? writer;
    private string? activeFile;

    internal bool IsRecording => capture is not null;

    internal string Start(VerbatimAppPaths paths)
    {
        if (capture is not null && activeFile is not null)
        {
            return activeFile;
        }

        paths.EnsureDirectoriesExist();
        activeFile = Path.Combine(paths.Recordings, $"recording-{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}.wav");
        capture = new WaveInEvent
        {
            DeviceNumber = 0,
            WaveFormat = new WaveFormat(16_000, 16, 1),
            BufferMilliseconds = 125,
        };
        writer = new WaveFileWriter(activeFile, capture.WaveFormat);
        capture.DataAvailable += (_, args) =>
        {
            writer?.Write(args.Buffer, 0, args.BytesRecorded);
            writer?.Flush();
        };
        capture.StartRecording();
        return activeFile;
    }

    internal string? Stop()
    {
        if (capture is null)
        {
            return activeFile;
        }

        capture.StopRecording();
        capture.Dispose();
        writer?.Dispose();
        capture = null;
        writer = null;
        return activeFile;
    }
}

internal sealed class WindowsRuntimeHealthService
{
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromSeconds(1) };
    private readonly VerbatimAppPaths paths;

    internal WindowsRuntimeHealthService(VerbatimAppPaths paths)
    {
        this.paths = paths;
    }

    internal async Task<Dictionary<string, RuntimeHealthSnapshot>> CaptureAsync()
    {
        paths.EnsureDirectoriesExist();
        var result = new Dictionary<string, RuntimeHealthSnapshot>
        {
            [ProviderIds.Whisper] = await CaptureRuntimeAsync(
                ProviderIds.Whisper,
                "whisper-server-windows-x64.exe",
                Path.Combine(paths.Runtime, "whisper-server-windows-x64.exe"),
                "http://127.0.0.1:8178/"),
            [ProviderIds.Parakeet] = await CaptureRuntimeAsync(
                ProviderIds.Parakeet,
                "sherpa-onnx-ws-windows-x64.exe",
                Path.Combine(paths.Runtime, "sherpa-onnx-ws-windows-x64.exe"),
                "ws://127.0.0.1:6006"),
        };
        return result;
    }

    private static async Task<RuntimeHealthSnapshot> CaptureRuntimeAsync(
        string providerId,
        string binaryName,
        string binaryPath,
        string endpoint)
    {
        var snapshot = new RuntimeHealthSnapshot
        {
            BinaryName = binaryName,
            BinaryPresent = File.Exists(binaryPath),
            Endpoint = endpoint,
            LastCheck = DateTimeOffset.UtcNow,
            State = File.Exists(binaryPath) ? "stopped" : "missing",
        };

        if (!snapshot.BinaryPresent)
        {
            snapshot.LastError = $"{binaryName} is not staged in Verbatim Runtime.";
            return snapshot;
        }

        if (providerId == ProviderIds.Whisper)
        {
            try
            {
                using var response = await HttpClient.GetAsync(endpoint);
                snapshot.State = response.IsSuccessStatusCode ? "ready" : "stopped";
            }
            catch (Exception error)
            {
                snapshot.State = "stopped";
                snapshot.LastError = error.Message;
            }
        }
        else
        {
            snapshot.State = "stopped";
        }

        return snapshot;
    }
}
