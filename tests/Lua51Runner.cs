using System;
using System.Runtime.InteropServices;

internal static class Lua51Runner
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetDllDirectory(string path);

    [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr luaL_newstate();

    [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void luaL_openlibs(IntPtr state);

    [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern int luaL_loadfile(IntPtr state, string filename);

    [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int lua_pcall(IntPtr state, int arguments, int results, int errorFunction);

    [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr lua_tolstring(IntPtr state, int index, out UIntPtr length);

    [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void lua_close(IntPtr state);

    private static string GetError(IntPtr state)
    {
        UIntPtr length;
        IntPtr text = lua_tolstring(state, -1, out length);
        return text == IntPtr.Zero
            ? "unknown Lua error"
            : Marshal.PtrToStringAnsi(text, checked((int)length.ToUInt64()));
    }

    private static int Run(string script)
    {
        IntPtr state = luaL_newstate();
        if (state == IntPtr.Zero)
        {
            Console.Error.WriteLine("Could not create Lua state.");
            return 1;
        }

        try
        {
            luaL_openlibs(state);
            int status = luaL_loadfile(state, script);
            if (status == 0)
            {
                status = lua_pcall(state, 0, 0, 0);
            }
            if (status != 0)
            {
                Console.Error.WriteLine(script + ": " + GetError(state));
                return 1;
            }
            return 0;
        }
        finally
        {
            lua_close(state);
        }
    }

    public static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine("Usage: Lua51Runner <directory containing lua51.dll> <script> [...]");
            return 2;
        }
        if (!SetDllDirectory(args[0]))
        {
            Console.Error.WriteLine("Could not configure the Lua DLL directory.");
            return 2;
        }

        int result = 0;
        for (int i = 1; i < args.Length; i++)
        {
            result |= Run(args[i]);
        }
        return result;
    }
}
