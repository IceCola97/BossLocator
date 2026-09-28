using System.Diagnostics;
using System.Text;

namespace FastLzInterop;

internal static class Program
{
    private static int Main(string[] args)
    {
        NativeResolver.Register();

        if (args.Length == 0 || args[0] is "-h" or "--help" or "/?")
        {
            PrintUsage();
            return args.Length == 0 ? 2 : 0;
        }

        try
        {
            return args[0] switch
            {
                "--gen" => Generate(args),
                "--batch" => Batch(args),
                _ => SingleFile(args[0]),
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("[fatal] " + ex);
            return 2;
        }
    }

    private static void PrintUsage()
    {
        Console.WriteLine("FastLZ interop tester (C DLL <-> pure-Lua fastlz.lua)");
        Console.WriteLine();
        Console.WriteLine("Usage:");
        Console.WriteLine("  FastLzInterop <file>                 cross-test a single file");
        Console.WriteLine("  FastLzInterop --batch <dir>          cross-test every file under a directory (recursive)");
        Console.WriteLine("  FastLzInterop --gen <dir> [n] [seed] generate n samples (default 1000)");
        Console.WriteLine();
        Console.WriteLine("Each file is tested both ways:");
        Console.WriteLine("  1) fastlz DLL compress   -> lua fastlz.decompress -> compare with original");
        Console.WriteLine("  2) lua fastlz.compress   -> fastlz DLL decompress -> compare with original");
    }

    private static string LuaScriptPath => Path.Combine(AppContext.BaseDirectory, "fastlz.lua");

    // ------------------------------------------------------------------
    //  Single file
    // ------------------------------------------------------------------
    private static int SingleFile(string path)
    {
        if (!File.Exists(path))
        {
            Console.Error.WriteLine($"File not found: {path}");
            return 2;
        }

        byte[] data = File.ReadAllBytes(path);

        Console.WriteLine($"Process arch : {(Environment.Is64BitProcess ? "x64" : "x86")}");
        Console.WriteLine($"Input file   : {path}");
        Console.WriteLine($"Input size   : {data.Length} bytes");

        using var lua = new LuaFastLz(LuaScriptPath);
        Console.WriteLine($"Lua runtime  : {LuaFastLz.LuaVersion}");
        Console.WriteLine();

        var result = CrossTest.Test(lua, path, data);
        PrintResult(result, verbose: true);

        Console.WriteLine();
        Console.WriteLine(result.Passed
            ? "RESULT: PASS (both directions reproduced the original data)"
            : result.Skipped
                ? "RESULT: SKIPPED"
                : "RESULT: FAIL");

        return result.Passed ? 0 : 1;
    }

    // ------------------------------------------------------------------
    //  Batch directory
    // ------------------------------------------------------------------
    private static int Batch(string[] args)
    {
        if (args.Length < 2 || !Directory.Exists(args[1]))
        {
            Console.Error.WriteLine("Usage: FastLzInterop --batch <dir>");
            return 2;
        }

        string root = Path.GetFullPath(args[1]);
        string[] files = Directory.GetFiles(root, "*", SearchOption.AllDirectories);
        Array.Sort(files, StringComparer.OrdinalIgnoreCase);

        long totalBytes = files.Sum(f => new FileInfo(f).Length);

        Console.WriteLine($"Process arch : {(Environment.Is64BitProcess ? "x64" : "x86")}");
        Console.WriteLine($"Directory    : {root} (recursive)");
        Console.WriteLine($"Files        : {files.Length} ({totalBytes} bytes)");

        var stopwatch = Stopwatch.StartNew();
        int pass = 0, fail = 0, skip = 0;
        long testedBytes = 0;
        var failures = new List<TestResult>();
        var skipped = new List<TestResult>();
        var failuresByCategory = new SortedDictionary<string, int>();
        var failuresByExtension = new SortedDictionary<string, int>();

        using (var lua = new LuaFastLz(LuaScriptPath))
        {
            Console.WriteLine($"Lua runtime  : {LuaFastLz.LuaVersion}");
            Console.WriteLine();

            int done = 0;
            foreach (string file in files)
            {
                byte[] data = File.ReadAllBytes(file);
                string relative = Path.GetRelativePath(root, file);
                var fileTimer = Stopwatch.StartNew();
                var result = CrossTest.Test(lua, relative, data);
                fileTimer.Stop();
                done++;

                if (fileTimer.Elapsed.TotalSeconds > 10)
                {
                    Console.WriteLine($"  [slow] {relative}: {fileTimer.Elapsed.TotalSeconds:F1}s ({data.Length} bytes)");
                }

                if (result.Skipped)
                {
                    skip++;
                    skipped.Add(result);
                }
                else
                {
                    testedBytes += data.Length;

                    if (result.Passed)
                    {
                        pass++;
                    }
                    else
                    {
                        fail++;
                        failures.Add(result);
                        string category = CategoryOf(result.Name);
                        failuresByCategory[category] = failuresByCategory.GetValueOrDefault(category) + 1;
                        string ext = Path.GetExtension(result.Name);
                        failuresByExtension[ext] = failuresByExtension.GetValueOrDefault(ext) + 1;
                    }
                }

                if (done % 100 == 0 || done == files.Length)
                {
                    Console.WriteLine($"  ... {done}/{files.Length} processed " +
                                      $"(pass={pass}, fail={fail}, skip={skip})");
                }
            }
        }

        stopwatch.Stop();

        Console.WriteLine();
        Console.WriteLine("================ SUMMARY ================");
        Console.WriteLine($"Total files : {files.Length}");
        Console.WriteLine($"PASS        : {pass}");
        Console.WriteLine($"FAIL        : {fail}");
        Console.WriteLine($"SKIP        : {skip}");
        Console.WriteLine($"Tested data : {testedBytes} bytes");
        Console.WriteLine($"Elapsed     : {stopwatch.Elapsed.TotalSeconds:F1}s");

        if (skip > 0)
        {
            Console.WriteLine();
            Console.WriteLine("Skipped files (up to 20):");
            foreach (var s in skipped.Take(20))
            {
                Console.WriteLine($"  [SKIP] {s.Name} ({s.OriginalLength} bytes): {s.Error}");
            }
        }

        if (failures.Count > 0)
        {
            Console.WriteLine();
            Console.WriteLine("Failures by sample category:");
            foreach (var kv in failuresByCategory)
            {
                Console.WriteLine($"  category {kv.Key}: {kv.Value}");
            }

            Console.WriteLine();
            Console.WriteLine("Failures by file extension:");
            foreach (var kv in failuresByExtension)
            {
                Console.WriteLine($"  '{kv.Key}': {kv.Value}");
            }

            Console.WriteLine();
            Console.WriteLine("First failures (up to 20):");
            foreach (var f in failures.Take(20))
            {
                PrintResult(f, verbose: true);
            }
        }

        Console.WriteLine();
        Console.WriteLine(fail == 0 ? "ALL PASSED" : "SOME FAILED");
        return fail == 0 ? 0 : 1;
    }

    private static string CategoryOf(string name)
    {
        // sample_0000_c3_n123.bin -> "c3"
        int c = name.IndexOf("_c", StringComparison.Ordinal);
        if (c < 0)
        {
            return "?";
        }

        int start = c + 2;
        int end = name.IndexOf('_', start);
        return end < 0 ? name[start..] : name[start..end];
    }

    // ------------------------------------------------------------------
    //  Sample generation
    // ------------------------------------------------------------------
    private static int Generate(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine("Usage: FastLzInterop --gen <dir> [n] [seed]");
            return 2;
        }

        string dir = args[1];
        int count = args.Length > 2 ? int.Parse(args[2]) : 1000;
        int seed = args.Length > 3 ? int.Parse(args[3]) : 12345;

        var files = SampleGen.Generate(dir, count, seed);
        long totalBytes = files.Sum(f => new FileInfo(f).Length);

        Console.WriteLine($"Generated {files.Count} samples into {dir} ({totalBytes} bytes total, seed={seed}).");
        return 0;
    }

    // ------------------------------------------------------------------
    //  Reporting
    // ------------------------------------------------------------------
    private static void PrintResult(TestResult r, bool verbose)
    {
        var sb = new StringBuilder();
        sb.Append($"[{r.Status}] {r.Name}  (orig={r.OriginalLength}B, cComp={r.CCompressedLength}B, luaComp={r.LuaCompressedLength}B)");

        if (verbose)
        {
            sb.AppendLine();
            sb.Append($"        dll-compress -> lua-decompress : {Mark(r.DllToLua)}");
            sb.AppendLine();
            sb.Append($"        lua-compress -> dll-decompress : {Mark(r.LuaToDll)}");
            sb.AppendLine();
            sb.Append($"        compressed streams byte-identical: {(r.CompressedBytesIdentical ? "yes" : "no (format still compatible)")}");

            if (!string.IsNullOrEmpty(r.Error))
            {
                sb.AppendLine();
                sb.Append($"        error: {r.Error}");
            }

            if (!string.IsNullOrEmpty(r.Detail))
            {
                sb.AppendLine();
                sb.Append($"        detail: {r.Detail}");
            }
        }

        Console.WriteLine(sb.ToString());
    }

    private static string Mark(bool? value) => value switch
    {
        true => "OK (matches original)",
        false => "MISMATCH",
        _ => "n/a",
    };
}
