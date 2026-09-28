using System.Text;

namespace FastLzInterop;

/// <summary>
/// Deterministic generator of varied test samples (different sizes and content
/// types). Sizes deliberately cover boundaries such as 4, 32, 65535 / 65536
/// (the level-1 / level-2 switch) and multi-hundred-KB inputs.
/// </summary>
internal static class SampleGen
{
    private const int Categories = 10;

    private static readonly int[] BoundarySizes =
    {
        1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 15, 16, 17, 31, 32, 33,
        63, 64, 65, 100, 127, 128, 129, 255, 256, 257, 511, 512, 513,
        1023, 1024, 1025, 4095, 4096, 4097, 8191, 8192, 8193,
        16384, 32767, 32768, 65534, 65535, 65536, 65537, 65538,
        100000, 131072, 200000,
    };

    private static readonly string[] Words =
    {
        "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
        "fastlz", "lua", "compression", "algorithm", "test", "sample",
        "data", "buffer", "stream", "level", "match", "literal", "distance",
    };

    public static List<string> Generate(string directory, int count, int seed)
    {
        Directory.CreateDirectory(directory);
        var created = new List<string>(count);
        var random = new Random(seed);

        for (int i = 0; i < count; i++)
        {
            int category = i % Categories;
            int size = i < BoundarySizes.Length ? BoundarySizes[i] : RandomSize(random);

            byte[] data = GenerateData(category, size, random);
            string fileName = $"sample_{i:D4}_c{category}_n{size}.bin";
            string fullPath = Path.Combine(directory, fileName);
            File.WriteAllBytes(fullPath, data);
            created.Add(fullPath);
        }

        return created;
    }

    private static int RandomSize(Random random)
    {
        int bucket = random.Next(100);
        if (bucket < 25)
        {
            return random.Next(1, 65);             // tiny
        }

        if (bucket < 55)
        {
            return random.Next(65, 4096);          // small
        }

        if (bucket < 85)
        {
            return random.Next(4096, 65536);       // medium -> level 1
        }

        return random.Next(65536, 262144);         // large  -> level 2
    }

    private static byte[] GenerateData(int category, int size, Random random)
    {
        return category switch
        {
            0 => RandomBytes(size, random),
            1 => Fill(size, 0x00),
            2 => Fill(size, (byte)random.Next(1, 256)),
            3 => Runs(size, random),
            4 => AsciiText(size, random),
            5 => RepeatingPattern(size, random),
            6 => Records(size, random),
            7 => SparseRandom(size, random),
            8 => Increment(size, random),
            _ => Mixed(size, random),
        };
    }

    private static byte[] RandomBytes(int size, Random random)
    {
        var data = new byte[size];
        random.NextBytes(data);
        return data;
    }

    private static byte[] Fill(int size, byte value)
    {
        var data = new byte[size];
        Array.Fill(data, value);
        return data;
    }

    private static byte[] Runs(int size, Random random)
    {
        var data = new byte[size];
        int pos = 0;
        while (pos < size)
        {
            byte value = (byte)random.Next(0, 4);              // few distinct values
            int run = random.Next(1, 40);
            for (int i = 0; i < run && pos < size; i++)
            {
                data[pos++] = value;
            }
        }

        return data;
    }

    private static byte[] AsciiText(int size, Random random)
    {
        var sb = new StringBuilder(size + 16);
        while (sb.Length < size)
        {
            sb.Append(Words[random.Next(Words.Length)]);
            sb.Append(random.Next(8) == 0 ? ".\n" : " ");
        }

        var text = Encoding.ASCII.GetBytes(sb.ToString());
        var data = new byte[size];
        Array.Copy(text, data, size);
        return data;
    }

    private static byte[] RepeatingPattern(int size, Random random)
    {
        int period = random.Next(1, 17);
        var pattern = new byte[period];
        random.NextBytes(pattern);

        var data = new byte[size];
        for (int i = 0; i < size; i++)
        {
            data[i] = pattern[i % period];
        }

        return data;
    }

    private static byte[] Records(int size, Random random)
    {
        const int recordSize = 32;
        var template = new byte[recordSize];
        random.NextBytes(template);

        var data = new byte[size];
        for (int i = 0; i < size; i++)
        {
            int offset = i % recordSize;
            byte value = template[offset];
            // Occasionally mutate a field so records are similar but not identical.
            if (offset < 4 && random.Next(6) == 0)
            {
                value = (byte)random.Next(256);
            }

            data[i] = value;
        }

        return data;
    }

    private static byte[] SparseRandom(int size, Random random)
    {
        var data = new byte[size];
        int count = Math.Max(1, size / 64);
        for (int i = 0; i < count; i++)
        {
            data[random.Next(size)] = (byte)random.Next(1, 256);
        }

        return data;
    }

    private static byte[] Increment(int size, Random random)
    {
        var data = new byte[size];
        int step = random.Next(1, 4);
        byte value = (byte)random.Next(256);
        for (int i = 0; i < size; i++)
        {
            data[i] = value;
            value = (byte)(value + step);
        }

        return data;
    }

    private static byte[] Mixed(int size, Random random)
    {
        var data = new byte[size];
        int pos = 0;
        while (pos < size)
        {
            int remaining = size - pos;
            int segment = Math.Min(remaining, random.Next(16, Math.Max(17, remaining)));
            switch (random.Next(4))
            {
                case 0:
                    for (int i = 0; i < segment; i++)
                    {
                        data[pos + i] = (byte)random.Next(256);
                    }

                    break;
                case 1:
                    Array.Clear(data, pos, segment);
                    break;
                case 2:
                    byte v = (byte)random.Next(256);
                    for (int i = 0; i < segment; i++)
                    {
                        data[pos + i] = v;
                    }

                    break;
                default:
                    for (int i = 0; i < segment; i++)
                    {
                        data[pos + i] = (byte)('A' + (i % 26));
                    }

                    break;
            }

            pos += segment;
        }

        return data;
    }
}
