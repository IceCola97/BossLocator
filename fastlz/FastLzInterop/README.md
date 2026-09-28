# FastLzInterop

一个 C# 命令行程序，用于验证纯 Lua 版 `fastlz.lua` 与真正的 C 版 FastLZ
（`fastlz.dll`）在压缩格式上是否互相兼容。

对每个输入文件执行双向交叉测试：

1. **DLL 压缩 → Lua 解压**：用 C 版 `fastlz_compress` 压缩，前面补上 4 字节大端长度头，
   再交给 `fastlz.lua` 的 `fastlz.decompress` 解压，比较是否等于原始数据。
2. **Lua 压缩 → DLL 解压**：用 `fastlz.lua` 的 `fastlz.compress` 压缩，去掉 4 字节长度头，
   再交给 C 版 `fastlz_decompress` 解压，比较是否等于原始数据。

两个方向都还原出原始数据即判定为通过。

## 关键点：位数必须一致

- 随附的 `lua51.dll` 是 **32 位 LuaJIT 2.0.4**。
- 仓库根目录的 `fastlz.dll` 是 **64 位**。

同一个进程不能同时加载 32 位和 64 位 DLL，因此本程序用**同一份**
`build\fastlz.c` 源码重新编译了一个 32 位 DLL（`native\fastlz_x86.dll`），
并让 C# 程序以 x86 方式运行。这样两者才能在同一进程内通过 P/Invoke 调用。

## 构建

```bat
:: 1) 用 x86 工具链编译 32 位 fastlz DLL
FastLzInterop\build_x86.bat

:: 2) 构建 C# 程序（RuntimeIdentifier=win-x86，32 位进程）
dotnet build -c Release FastLzInterop\FastLzInterop.csproj
```

## 用法

```bat
:: 交叉测试单个文件（题目要求的命令形式）
FastLzInterop <file>

:: 生成测试样例
FastLzInterop --gen <dir> [数量] [随机种子]

:: 批量测试目录下的全部文件（递归）
FastLzInterop --batch <dir>
```

运行示例：

```bat
cd FastLzInterop
dotnet run -c Release -- --gen ..\samples 1000 20260928
dotnet run -c Release -- --batch ..\samples
```

## 数据格式说明

| 实现 | 接口 | 数据格式 |
| --- | --- | --- |
| C `fastlz.dll` | `fastlz_compress` / `fastlz_decompress` | 裸 FastLZ 流（无头部） |
| `fastlz.lua` | `fastlz.compress` / `fastlz.decompress` | 4 字节大端原始长度 + 裸 FastLZ 流 |

交叉测试时程序会补/去这 4 字节头部。压缩级别选择规则一致：输入 < 65536 字节用
level 1，否则用 level 2；解压端根据流首字节自动识别级别。

## 关于压缩结果不完全一致

本仓库的 C 源码是 FastLZ **0.5.0**（`build\fastlz.c`），而 `fastlz.lua` 移植自
lua-fastlz 打包的 FastLZ **0.1.0**。两者：

- **哈希函数不同**（0.5.0 用乘法哈希，0.1.0 用异或移位哈希）；
- **边界常量不同**（`ip_bound = length-4` vs `length-2`）。

因此二者对同一输入选择出的匹配可能不同，**压缩后的字节流通常不相同**（程序中会显示
`compressed streams byte-identical: no`）。但二者的**格式完全兼容**，交叉解压都能正确
还原，这正是本测试验证的目标。

## 真实数据验证结果

对 `real` 目录（递归遍历）的全部真实文件进行了交叉测试：

| 指标 | 数值 |
| --- | --- |
| 文件总数 | 2933 |
| 已测数据量 | 139,039,716 字节（约 132.6 MiB） |
| 通过 | 2931 |
| 失败 | 0 |
| 跳过 | 2（均为 0 字节的空占位文件） |
| 耗时 | 约 10.8 秒 |

覆盖多种真实文件类型（`.bin`、`.png_petri`、`.xml`、`.csv`、`.wak`、`.bmp`、`.lua` 等），
最大单个文件 42 MB（`data\data.wak`），均双向还原一致。

> 空文件会被跳过：`fastlz.lua` 的 `compress` 对空输入返回 `nil`（与 lua-fastlz 行为一致），
> 无法进行有意义的压缩测试，因此标记为 SKIP。

## 修复记录

测试发现 1/1000 的样本在 Lua 压缩 level 2 时失败：匹配一直延伸到输入末尾时，
边界哈希更新会读取末尾之后的 1~2 个字节。C 版也会这样读，但依赖调用方缓冲区预留的
富余空间；纯 Lua 的 `string.byte` 越界返回 `nil`，导致算术运算报错。

已在 `fastlz.lua` 的边界哈希更新处对越界字节用 `0` 顶替（该哈希表项之后不会被使用，
不影响压缩结果）。
