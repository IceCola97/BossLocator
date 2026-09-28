using System.Runtime.InteropServices;

namespace FastLzInterop;

/// <summary>
/// Hosts the pure-Lua FastLZ module (fastlz.lua) inside the bundled
/// lua51.dll (LuaJIT 2.0.4) and drives it through the Lua C API.
///
/// The Lua module follows the lua-fastlz data format:
///   4-byte big-endian original length, followed by the raw FastLZ stream.
/// </summary>
internal sealed class LuaFastLz : IDisposable
{
    private const string Dll = "lua51.dll";

    private const int LUA_TNIL = 0;
    private const int LUA_TSTRING = 4;

    // In Lua 5.1 lua_getglobal/lua_setglobal are macros over the globals
    // pseudo-index, and are therefore not exported by lua51.dll.
    private const int LUA_GLOBALSINDEX = -10002;

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr luaL_newstate();

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern void luaL_openlibs(IntPtr L);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern int luaL_loadfile(IntPtr L, string filename);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int lua_pcall(IntPtr L, int nargs, int nresults, int errfunc);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern void lua_setfield(IntPtr L, int idx, string name);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern void lua_getfield(IntPtr L, int idx, string k);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr lua_tolstring(IntPtr L, int idx, out UIntPtr len);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern void lua_pushlstring(IntPtr L, byte[] s, UIntPtr len);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int lua_gettop(IntPtr L);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern void lua_settop(IntPtr L, int idx);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int lua_type(IntPtr L, int idx);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern void lua_close(IntPtr L);

    private IntPtr _L;

    /// <summary>Version string reported by the Lua runtime.</summary>
    public static string LuaVersion { get; private set; } = "unknown";

    public LuaFastLz(string luaScriptPath)
    {
        _L = luaL_newstate();
        if (_L == IntPtr.Zero)
        {
            throw new InvalidOperationException(
                "luaL_newstate failed. Is lua51.dll present and of the same bitness as this process?");
        }

        luaL_openlibs(_L);

        int rc = luaL_loadfile(_L, luaScriptPath);
        if (rc != 0)
        {
            string err = PopError();
            lua_close(_L);
            _L = IntPtr.Zero;
            throw new InvalidOperationException($"Cannot load '{luaScriptPath}': {err}");
        }

        rc = lua_pcall(_L, 0, 1, 0);
        if (rc != 0)
        {
            string err = PopError();
            lua_close(_L);
            _L = IntPtr.Zero;
            throw new InvalidOperationException($"Cannot run '{luaScriptPath}': {err}");
        }

        // The chunk returns the module table; publish it as the global "fastlz".
        lua_setfield(_L, LUA_GLOBALSINDEX, "fastlz");
        LuaVersion = EvalString("return _VERSION");
    }

    public byte[]? Compress(byte[] data) => Invoke("compress", data);

    public byte[]? Decompress(byte[] data) => Invoke("decompress", data);

    private byte[]? Invoke(string functionName, byte[] argument)
    {
        int baseTop = lua_gettop(_L);
        try
        {
            lua_getfield(_L, LUA_GLOBALSINDEX, "fastlz");  // fastlz
            lua_getfield(_L, -1, functionName);             // fastlz, fn
            lua_pushlstring(_L, argument, (UIntPtr)argument.Length);

            int rc = lua_pcall(_L, 1, 1, 0);
            if (rc != 0)
            {
                string err = LuaToString(-1);
                throw new InvalidOperationException($"lua fastlz.{functionName} raised: {err}");
            }

            if (lua_type(_L, -1) != LUA_TSTRING)
            {
                // The module returns nil for invalid input / failed decompression.
                return null;
            }

            IntPtr ptr = lua_tolstring(_L, -1, out UIntPtr len);
            var result = new byte[(int)len];
            if (len != UIntPtr.Zero)
            {
                Marshal.Copy(ptr, result, 0, (int)len);
            }

            return result;
        }
        finally
        {
            lua_settop(_L, baseTop);
        }
    }

    private string EvalString(string luaCode)
    {
        int baseTop = lua_gettop(_L);
        try
        {
            int rc = luaL_loadstring(_L, luaCode);
            if (rc != 0)
            {
                lua_settop(_L, baseTop);
                return "unknown";
            }

            rc = lua_pcall(_L, 0, 1, 0);
            if (rc != 0)
            {
                lua_settop(_L, baseTop);
                return "unknown";
            }

            return LuaToString(-1);
        }
        finally
        {
            lua_settop(_L, baseTop);
        }
    }

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern int luaL_loadstring(IntPtr L, string s);

    private string LuaToString(int idx)
    {
        IntPtr ptr = lua_tolstring(_L, idx, out UIntPtr len);
        if (ptr == IntPtr.Zero)
        {
            return lua_type(_L, idx) == LUA_TNIL ? "nil" : "(non-string)";
        }

        return Marshal.PtrToStringAnsi(ptr, (int)len) ?? string.Empty;
    }

    private string PopError()
    {
        string message = LuaToString(-1);
        lua_settop(_L, -2);
        return message;
    }

    public void Dispose()
    {
        if (_L != IntPtr.Zero)
        {
            lua_close(_L);
            _L = IntPtr.Zero;
        }
    }
}
