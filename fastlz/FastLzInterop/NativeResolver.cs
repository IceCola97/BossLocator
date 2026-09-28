using System.Reflection;
using System.Runtime.InteropServices;

namespace FastLzInterop;

/// <summary>
/// Resolves the native DLLs (lua51.dll, fastlz_x86.dll) from the application
/// directory so the program works no matter what the current directory is.
/// </summary>
internal static class NativeResolver
{
    public static void Register()
    {
        NativeLibrary.SetDllImportResolver(typeof(NativeResolver).Assembly, Resolve);
    }

    private static IntPtr Resolve(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
    {
        string? candidate = libraryName switch
        {
            "fastlz_x86.dll" => Path.Combine(AppContext.BaseDirectory, "fastlz_x86.dll"),
            "lua51.dll" => Path.Combine(AppContext.BaseDirectory, "lua51.dll"),
            _ => null,
        };

        if (candidate is not null && File.Exists(candidate))
        {
            return NativeLibrary.Load(candidate);
        }

        return IntPtr.Zero; // fall back to default search
    }
}
