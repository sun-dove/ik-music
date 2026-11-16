using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

// 进程只拥有专用WebView2配置；不注册脚本可调用的宿主对象或消息处理器。
internal sealed class YueyinLxHost : Form
{
    private readonly string profile;
    private readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 3 * 1024 * 1024 };
    private readonly WebView2 view = new WebView2();
    private bool initialNavigation = true;
    private static IntPtr job;
    private static string token;
    private static void Trace(string stage)
    {
        if (Environment.GetEnvironmentVariable("YUEYIN_LX_DIAGNOSTICS") == "1") Console.Error.WriteLine(stage);
    }

    [STAThread]
    private static int Main(string[] args)
    {
        Console.SetOut(new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true });
        token = Environment.GetEnvironmentVariable("YUEYIN_LX_TOKEN");
        Environment.SetEnvironmentVariable("YUEYIN_LX_TOKEN", null);
        if (args.Length != 1 || token == null || token.Length != 64 || !Directory.Exists(args[0]) || !ConstrainProcess())
        {
            Console.WriteLine("{\"state\":\"unavailable\"}");
            return 1;
        }
        Application.EnableVisualStyles();
        Trace("window");
        Application.Run(new YueyinLxHost(args[0]));
        return 0;
    }

    private YueyinLxHost(string profile)
    {
        this.profile = profile;
        ShowInTaskbar = false;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Location = new Point(-32000, -32000);
        Size = new Size(8, 8);
        Opacity = 0;
        view.Dock = DockStyle.Fill;
        Controls.Add(view);
        Load += async (sender, e) => await Run();
        FormClosed += (sender, e) => view.Dispose();
    }

    private async Task Run()
    {
        try
        {
            Trace("environment");
            var options = new CoreWebView2EnvironmentOptions("--disable-background-networking --disable-extensions --disable-sync --no-proxy-server --disable-gpu --disable-breakpad");
            var environment = await CoreWebView2Environment.CreateAsync(null, profile, options);
            Trace("controller");
            await view.EnsureCoreWebView2Async(environment);
            Trace("settings");
            var core = view.CoreWebView2;
            core.ProcessFailed += (sender, e) => Trace("process-failed:" + e.ProcessFailedKind + ":" + e.Reason + ":" + e.ExitCode);
            var settings = core.Settings;
            settings.AreHostObjectsAllowed = false;
            settings.IsWebMessageEnabled = false;
            settings.AreDevToolsEnabled = false;
            settings.AreDefaultContextMenusEnabled = false;
            settings.AreDefaultScriptDialogsEnabled = false;
            settings.AreBrowserAcceleratorKeysEnabled = false;
            settings.IsStatusBarEnabled = false;
            settings.IsBuiltInErrorPageEnabled = false;
            settings.IsPasswordAutosaveEnabled = false;
            settings.IsGeneralAutofillEnabled = false;
            core.NavigationStarting += (sender, e) => { if (!initialNavigation) e.Cancel = true; };
            core.FrameNavigationStarting += (sender, e) => { e.Cancel = true; };
            core.NewWindowRequested += (sender, e) => { e.Handled = true; };
            core.PermissionRequested += (sender, e) => { e.State = CoreWebView2PermissionState.Deny; };
            core.DownloadStarting += (sender, e) => { e.Cancel = true; };
            core.LaunchingExternalUriScheme += (sender, e) => { e.Cancel = true; };
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += (sender, e) => {
                e.Response = environment.CreateWebResourceResponse(new MemoryStream(new byte[0]), 403, "Blocked", "Content-Type: text/plain\r\n");
            };
            Trace("document");
            var loaded = new TaskCompletionSource<bool>();
            core.NavigationCompleted += (sender, e) => {
                initialNavigation = false;
                loaded.TrySetResult(e.IsSuccess);
            };
            core.NavigateToString("<!doctype html><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; connect-src 'none'; frame-src 'none'; child-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\"><body></body>");
            if (!await loaded.Task) throw new InvalidOperationException();
            Trace("network-boundary");
            await core.CallDevToolsProtocolMethodAsync("Network.enable", "{}");
            await core.CallDevToolsProtocolMethodAsync("Network.setBlockedURLs", "{\"urls\":[\"*\"]}");
            var hidden = await core.ExecuteScriptAsync("Object.defineProperty(window,'chrome',{value:undefined,writable:false,configurable:false});typeof chrome");
            if (hidden != "\"undefined\"") throw new InvalidOperationException();
            Trace("ready");
            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start(1);
            Console.WriteLine(json.Serialize(new { state = "ready", port = ((IPEndPoint)listener.LocalEndpoint).Port }));
            var client = await listener.AcceptTcpClientAsync();
            listener.Stop();
            var input = client.GetStream();
            while (true)
            {
                var line = await Task.Run(() => ReadRequest(input));
                if (line == null || line.Length > 3 * 1024 * 1024) break;
                int id = 0;
                try
                {
                    var request = json.Deserialize<Dictionary<string, object>>(line);
                    if (!request.ContainsKey("token") || !String.Equals(request["token"] as string, token, StringComparison.Ordinal)) break;
                    id = Convert.ToInt32(request["id"]);
                    var code = request["code"] as string;
                    if (code == null || Encoding.UTF8.GetByteCount(code) > 2 * 1024 * 1024) throw new InvalidOperationException();
                    Trace("evaluate");
                    var encoded = await core.CallDevToolsProtocolMethodAsync("Runtime.evaluate", json.Serialize(new { expression = code, returnByValue = true, awaitPromise = false }));
                    Trace("evaluated");
                    var evaluation = json.Deserialize<Dictionary<string, object>>(encoded);
                    if (evaluation.ContainsKey("exceptionDetails")) throw new InvalidOperationException();
                    var returned = evaluation["result"] as Dictionary<string, object>;
                    object result = returned != null && returned.ContainsKey("value") ? returned["value"] : null;
                    Console.WriteLine(json.Serialize(new { id = id, result = result == null ? "" : Convert.ToString(result) }));
                }
                catch
                {
                    // 不回传脚本内容、异常正文或配置目录。
                    Console.WriteLine(json.Serialize(new { id = id, error = "script" }));
                }
            }
            client.Close();
        }
        catch
        {
            Console.WriteLine("{\"state\":\"unavailable\"}");
        }
        Close();
    }

    private static string ReadRequest(Stream input)
    {
        var header = new byte[4];
        if (!ReadExactly(input, header)) return null;
        var length = BitConverter.ToInt32(header, 0);
        if (length <= 0 || length > 3 * 1024 * 1024) return null;
        var payload = new byte[length];
        return ReadExactly(input, payload) ? Encoding.UTF8.GetString(payload) : null;
    }

    private static bool ReadExactly(Stream input, byte[] buffer)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var count = input.Read(buffer, offset, buffer.Length - offset);
            if (count == 0) return false;
            offset += count;
        }
        return true;
    }

    private static bool ConstrainProcess()
    {
        job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) return false;
        var limits = new ExtendedLimits();
        limits.BasicLimitInformation.LimitFlags = 0x2000 | 0x200 | 0x100 | 0x4;
        limits.BasicLimitInformation.PerJobUserTimeLimit = 30L * 10000000;
        limits.ProcessMemoryLimit = new UIntPtr(512U * 1024 * 1024);
        limits.JobMemoryLimit = new UIntPtr(1024U * 1024 * 1024);
        var size = Marshal.SizeOf(limits);
        var pointer = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(limits, pointer, false);
            if (!SetInformationJobObject(job, 9, pointer, (uint)size)) return false;
        }
        finally { Marshal.FreeHGlobal(pointer); }
        return AssignProcessToJobObject(job, GetCurrentProcess());
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BasicLimits
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters { public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount; }
    [StructLayout(LayoutKind.Sequential)]
    private struct ExtendedLimits
    {
        public BasicLimits BasicLimitInformation;
        public IoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll")] private static extern bool SetInformationJobObject(IntPtr job, int type, IntPtr info, uint length);
    [DllImport("kernel32.dll")] private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
}
