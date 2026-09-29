// Minimal Lua 5.1 (x86) host that runs the NoitaSaveTest scripts.
//
// The Lua side never shells out: this host performs the directory enumeration
// and hands it over as the NOITA_LIST_FILES global, so saves/save_scanner.lua
// and saves/entity_parser.lua stay platform independent.
//
// Usage: NoitaSaveTest [saveDirectory | entities_*.bin] [script]
//   saveDirectory  : a save<N> folder (the scanner reads its world/ sub folder);
//                    a whole save tree is accepted and its first save<N> is used
//   default        : the first save<N> of the nearest sample_save directory
//   default script : scan_entities.lua next to this executable
using System.Runtime.InteropServices;

internal static class Program
{
    private const string LuaDll = "lua51.dll";
    private const int Globals = -10002;

    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr luaL_newstate();
    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl)] private static extern void luaL_openlibs(IntPtr state);
    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)] private static extern int luaL_loadfile(IntPtr state, string file);
    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl)] private static extern int lua_pcall(IntPtr state, int nargs, int nresults, int errfunc);
    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)] private static extern void lua_pushstring(IntPtr state, string value);
    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)] private static extern void lua_setfield(IntPtr state, int index, string name);
    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr lua_tolstring(IntPtr state, int index, out UIntPtr length);
    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl)] private static extern void lua_close(IntPtr state);
    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl)] private static extern void lua_createtable(IntPtr state, int narr, int nrec);
    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl)] private static extern void lua_rawseti(IntPtr state, int index, int n);
    [DllImport(LuaDll, CallingConvention = CallingConvention.Cdecl)] private static extern void lua_pushcclosure(IntPtr state, IntPtr fn, int n);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int LuaCFunction(IntPtr state);

    // Kept in a static field so the GC cannot collect the thunk.
    private static readonly LuaCFunction ListFilesThunk = ListFiles;

    private static string LuaError(IntPtr state)
    {
        var ptr = lua_tolstring(state, -1, out var len);
        return ptr == IntPtr.Zero ? "unknown Lua error" : Marshal.PtrToStringAnsi(ptr, checked((int)len)) ?? "unknown Lua error";
    }

    private static string Argument(IntPtr state, int index)
    {
        var ptr = lua_tolstring(state, index, out var len);
        return ptr == IntPtr.Zero ? string.Empty : Marshal.PtrToStringAnsi(ptr, checked((int)len.ToUInt64())) ?? string.Empty;
    }

    // Recursive file listing: unreadable directories are skipped, files are
    // reported with the separator the host OS uses.
    private static IEnumerable<string> EnumerateFiles(string root)
    {
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.Count > 0)
        {
            string directory = pending.Pop();
            string[] entries;
            try { entries = Directory.GetFileSystemEntries(directory); }
            catch { continue; }
            foreach (string entry in entries)
            {
                if (Directory.Exists(entry)) pending.Push(entry);
                else yield return entry;
            }
        }
    }

    // NOITA_LIST_FILES(root) -> array of every file path below root.
    private static int ListFiles(IntPtr state)
    {
        string root = Argument(state, 1);
        lua_createtable(state, 0, 0);
        int count = 0;
        if (root.Length > 0 && Directory.Exists(root))
        {
            foreach (string file in EnumerateFiles(root))
            {
                lua_pushstring(state, file);
                lua_rawseti(state, -2, ++count);
            }
        }
        return 1;
    }

    private static void SetGlobalString(IntPtr state, string name, string value)
    {
        lua_pushstring(state, value);
        lua_setfield(state, Globals, name);
    }

    private static void SetGlobalFunction(IntPtr state, string name, LuaCFunction fn)
    {
        lua_pushcclosure(state, Marshal.GetFunctionPointerForDelegate(fn), 0);
        lua_setfield(state, Globals, name);
    }

    // Default save directory: the nearest sample save_N_ folder below a
    // sample_save directory in the source tree (the test data is not copied to
    // the build output).
    private static string? FindSampleSave()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        for (int depth = 0; directory != null && depth < 8; depth++, directory = directory.Parent)
        {
            string candidate = Path.Combine(directory.FullName, "sample_save");
            if (Directory.Exists(candidate)) return candidate;
        }
        return null;
    }

    private static readonly System.Text.RegularExpressions.Regex SaveDirectory = new("^save\\d+$");

    // The scanner works on a save<N> directory (it looks inside its world/).
    // Accepting a whole save tree here keeps the command line forgiving: when
    // the given path holds save<N> sub directories, the first one is used.
    private static string NormalizeSaveDirectory(string path)
    {
        if (!Directory.Exists(path)) return path; // a single entities_*.bin file
        if (Directory.Exists(Path.Combine(path, "world"))) return path;
        string[] candidates;
        try { candidates = Directory.GetDirectories(path); }
        catch { return path; }
        Array.Sort(candidates, StringComparer.OrdinalIgnoreCase);
        foreach (string candidate in candidates)
        {
            if (SaveDirectory.IsMatch(Path.GetFileName(candidate)))
            {
                Console.WriteLine($"[C#] using save directory {candidate}");
                return candidate;
            }
        }
        return path;
    }

    private static string ResolveRoot(string[] args)
    {
        if (args.Length > 0) return NormalizeSaveDirectory(Path.GetFullPath(args[0]));
        string? sample = FindSampleSave();
        if (sample != null) return NormalizeSaveDirectory(sample);
        return NormalizeSaveDirectory(Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "sample_save")));
    }

    public static int Main(string[] args)
    {
        string root = ResolveRoot(args);
        string script = args.Length > 1 ? Path.GetFullPath(args[1]) : Path.Combine(AppContext.BaseDirectory, "scan_entities.lua");
        string fastlz = Path.Combine(AppContext.BaseDirectory, "fastlz.lua");
        if (!Directory.Exists(root) && !File.Exists(root)) { Console.Error.WriteLine($"Input path does not exist: {root}"); return 2; }
        if (!File.Exists(script)) { Console.Error.WriteLine($"Lua script does not exist: {script}"); return 2; }
        Console.WriteLine($"[C#] Lua 5.1 host starting; root={root} script={Path.GetFileName(script)}");
        IntPtr state = luaL_newstate();
        if (state == IntPtr.Zero) { Console.Error.WriteLine("[C#] luaL_newstate failed (check x86 lua51.dll)."); return 1; }
        try
        {
            luaL_openlibs(state);
            int rc = luaL_loadfile(state, script);
            if (rc == 0)
            {
                SetGlobalString(state, "NOITA_SAVE_DIR_ARG", root);
                SetGlobalString(state, "NOITA_SAVES_DIR", AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
                SetGlobalString(state, "NOITA_FASTLZ_SCRIPT_ARG", fastlz);
                SetGlobalFunction(state, "NOITA_LIST_FILES", ListFilesThunk);
                rc = lua_pcall(state, 0, 0, 0);
            }
            if (rc != 0) { Console.Error.WriteLine($"[C#] Lua failure: {LuaError(state)}"); return 1; }
            Console.WriteLine("[C#] Lua script completed successfully.");
            return 0;
        }
        finally { lua_close(state); }
    }
}
