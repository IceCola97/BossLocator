using System.Runtime.InteropServices;

namespace FastLzInterop;

/// <summary>
/// P/Invoke wrapper around the real C FastLZ library.
/// The DLL is built from build\fastlz.c (FastLZ 0.5.0). It exposes the raw
/// FastLZ API: no length header, unlike the lua-fastlz binding.
///   fastlz_compress(input, length, output)            -> compressed size
///   fastlz_compress_level(level, input, length, out)   -> compressed size
///   fastlz_decompress(input, length, output, maxout)   -> decompressed size (0 on error)
/// </summary>
internal static class FastLzNative
{
    private const string Dll = "fastlz_x86.dll";

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int fastlz_compress(IntPtr input, int length, IntPtr output);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int fastlz_compress_level(int level, IntPtr input, int length, IntPtr output);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int fastlz_decompress(IntPtr input, int length, IntPtr output, int maxout);

    /// <summary>Compress with the same automatic level selection as the C library.</summary>
    public static byte[] Compress(byte[] data) => CompressLevel(0, data);

    /// <summary>Compress with an explicit level (1 or 2). Pass 0 to auto-select.</summary>
    public static byte[] CompressLevel(int level, byte[] data)
    {
        int inLen = data.Length;
        int outCap = OutputCapacity(inLen);

        IntPtr input = AllocInput(data);
        IntPtr output = Marshal.AllocHGlobal(outCap);
        try
        {
            int n = level == 0
                ? fastlz_compress(input, inLen, output)
                : fastlz_compress_level(level, input, inLen, output);

            if (n < 0)
            {
                throw new InvalidOperationException($"fastlz_compress returned {n}");
            }

            var result = new byte[n];
            if (n > 0)
            {
                Marshal.Copy(output, result, 0, n);
            }

            return result;
        }
        finally
        {
            Marshal.FreeHGlobal(input);
            Marshal.FreeHGlobal(output);
        }
    }

    /// <summary>Decompress a raw FastLZ stream (no length header). Returns null on error.</summary>
    public static byte[]? Decompress(byte[] compressed, int maxOut)
    {
        int outCap = Math.Max(maxOut, 1) + 64;

        IntPtr input = AllocInput(compressed);
        IntPtr output = Marshal.AllocHGlobal(outCap);
        try
        {
            int n = fastlz_decompress(input, compressed.Length, output, maxOut);
            if (n <= 0)
            {
                return null;
            }

            var result = new byte[n];
            Marshal.Copy(output, result, 0, n);
            return result;
        }
        finally
        {
            Marshal.FreeHGlobal(input);
            Marshal.FreeHGlobal(output);
        }
    }

    private static int OutputCapacity(int inLen)
    {
        // FastLZ docs: output must be >= input * 1.05 and >= 66 bytes.
        return Math.Max(66, inLen + inLen / 20 + 66) + 64;
    }

    /// <summary>
    /// Copies the payload into unmanaged memory with 64 bytes of zero padding.
    /// The C code performs word-sized reads that may look slightly past the
    /// logical end of the buffer; the padding keeps those reads in-bounds.
    /// </summary>
    private static IntPtr AllocInput(byte[] data)
    {
        int cap = data.Length + 64;
        IntPtr p = Marshal.AllocHGlobal(cap);
        if (data.Length > 0)
        {
            Marshal.Copy(data, 0, p, data.Length);
        }

        for (int i = 0; i < 64; i++)
        {
            Marshal.WriteByte(p, data.Length + i, 0);
        }

        return p;
    }
}
