using System.Text;

namespace FastLzInterop;

internal sealed class TestResult
{
    public string Name { get; set; } = string.Empty;
    public int OriginalLength { get; set; }

    /// <summary>C-DLL compress -> Lua decompress equals the original?</summary>
    public bool? DllToLua { get; set; }

    /// <summary>Lua compress -> C-DLL decompress equals the original?</summary>
    public bool? LuaToDll { get; set; }

    public int CCompressedLength { get; set; }
    public int LuaCompressedLength { get; set; }
    public bool CompressedBytesIdentical { get; set; }
    public string? Error { get; set; }
    public string? Detail { get; set; }

    public bool Skipped => DllToLua is null && LuaToDll is null;

    public bool Passed => DllToLua == true && LuaToDll == true;

    public string Status => Skipped ? "SKIP" : (Passed ? "PASS" : "FAIL");
}

/// <summary>
/// Runs the bidirectional interoperability test between the C FastLZ DLL and
/// the pure-Lua fastlz.lua module for a single data block:
///
///   1) DLL compress  -> Lua decompress  -> must equal the original
///   2) Lua compress  -> DLL decompress  -> must equal the original
///
/// The two libraries use the same logical FastLZ format, but the Lua module
/// (like the lua-fastlz binding) stores a 4-byte big-endian length header in
/// front of the raw stream. The tests add/strip that header as required.
/// </summary>
internal sealed class CrossTest
{
    public static TestResult Test(LuaFastLz lua, string name, byte[] data)
    {
        var result = new TestResult { Name = name, OriginalLength = data.Length };

        try
        {
            if (data.Length == 0)
            {
                result.Error = "empty input (Lua compress returns nil); case skipped";
                return result;
            }

            // ---------------- Direction 1: C DLL compress -> Lua decompress ----------------
            byte[] cRaw = FastLzNative.Compress(data);
            result.CCompressedLength = cRaw.Length;

            byte[] withHeader = PrependLengthHeader(data.Length, cRaw);
            byte[]? luaDecoded = lua.Decompress(withHeader);
            result.DllToLua = luaDecoded is not null && BytesEqual(luaDecoded, data);

            if (result.DllToLua != true)
            {
                result.Detail = DifferenceReport("DLL-compress -> Lua-decompress", data, luaDecoded);
            }

            // ---------------- Direction 2: Lua compress -> C DLL decompress ----------------
            byte[]? luaFull = lua.Compress(data);
            if (luaFull is null)
            {
                result.LuaToDll = false;
                result.Error = "lua fastlz.compress returned nil";
                return result;
            }

            if (luaFull.Length < 4)
            {
                result.LuaToDll = false;
                result.Error = $"lua output too short ({luaFull.Length} bytes)";
                return result;
            }

            int declaredLen = ReadBigEndianInt32(luaFull);
            byte[] luaRaw = luaFull[4..];
            result.LuaCompressedLength = luaRaw.Length;

            if (declaredLen != data.Length)
            {
                result.LuaToDll = false;
                result.Error = $"lua header length {declaredLen} != original {data.Length}";
                return result;
            }

            byte[]? cDecoded = FastLzNative.Decompress(luaRaw, data.Length);
            result.LuaToDll = cDecoded is not null && BytesEqual(cDecoded, data);

            if (result.LuaToDll != true)
            {
                result.Detail = DifferenceReport("Lua-compress -> DLL-decompress", data, cDecoded);
            }

            // Extra information (not a pass/fail criterion): would both libraries
            // produce byte-identical compressed streams?
            result.CompressedBytesIdentical =
                cRaw.Length == luaRaw.Length && cRaw.AsSpan().SequenceEqual(luaRaw);
        }
        catch (Exception ex)
        {
            result.Error = ex.GetType().Name + ": " + ex.Message;
            result.DllToLua ??= false;
            result.LuaToDll ??= false;
        }

        return result;
    }

    private static byte[] PrependLengthHeader(int length, byte[] body)
    {
        var buffer = new byte[body.Length + 4];
        buffer[0] = (byte)((length >> 24) & 0xFF);
        buffer[1] = (byte)((length >> 16) & 0xFF);
        buffer[2] = (byte)((length >> 8) & 0xFF);
        buffer[3] = (byte)(length & 0xFF);
        Buffer.BlockCopy(body, 0, buffer, 4, body.Length);
        return buffer;
    }

    private static int ReadBigEndianInt32(byte[] data)
    {
        return (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
    }

    private static bool BytesEqual(byte[] a, byte[] b)
    {
        return a.AsSpan().SequenceEqual(b);
    }

    private static string DifferenceReport(string stage, byte[] original, byte[]? produced)
    {
        if (produced is null)
        {
            return $"{stage}: produced nil (decompression failed)";
        }

        int n = Math.Min(original.Length, produced.Length);
        int firstDiff = -1;
        for (int i = 0; i < n; i++)
        {
            if (original[i] != produced[i])
            {
                firstDiff = i;
                break;
            }
        }

        var sb = new StringBuilder();
        sb.Append($"{stage}: original={original.Length}B produced={produced.Length}B");
        if (firstDiff >= 0)
        {
            sb.Append($", first diff at offset {firstDiff}: original=0x{original[firstDiff]:X2} produced=0x{produced[firstDiff]:X2}");
        }
        else if (original.Length != produced.Length)
        {
            sb.Append(", prefix identical but lengths differ");
        }

        return sb.ToString();
    }
}
