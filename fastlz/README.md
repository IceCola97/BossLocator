# fastlz.lua（纯 Lua 版 FastLZ）

[English](README.en.md) | [简体中文](README.md)

> 本移植库及其测试均由 AI 辅助完成，详见 [AI 辅助说明](#ai-辅助说明)。

## 简介

`fastlz.lua` 是 FastLZ 压缩算法的**纯 Lua 移植版**，不含任何原生依赖。它由 AI 辅助
从 lua-fastlz 仓库所打包的 FastLZ C 实现（FastLZ 0.1.0，作者 Ariya Hidayat，MIT 许可）
移植而来，数据格式与 lua-fastlz 的 C 模块完全兼容：

- 压缩结果头部带 4 字节大端序（网络序）的原始数据长度，之后是裸 FastLZ 压缩流；
- 输入小于 65536 字节时使用 level 1，否则使用 level 2（与 C 版规则一致）；
- 解压时根据流首字节自动识别 level 1 / level 2，因此可以解压 C 版
  `fastlz_compress` 产出的数据，反之亦然。

兼容 Lua 5.1 / 5.2 / 5.3 / 5.4 及 LuaJIT（自动选择位运算实现）。

```lua
local fastlz = require("fastlz")
local compressed = fastlz.compress(data)   -- 失败返回 nil
local original   = fastlz.decompress(compressed)
```

## 兼容性测试

为验证格式兼容性，将本纯 Lua 实现与 **FastLZ 仓库的最新版编译产物**做了双向交叉
对比测试。C 参考实现由仓库内的 `build/fastlz.c`（FastLZ 0.5.0，即该仓库最新发布版）
编译为原生 `fastlz.dll`：

1. **DLL 压缩 → Lua 解压**：C 版压缩并补上 4 字节长度头，交给 `fastlz.lua` 解压；
2. **Lua 压缩 → DLL 解压**：`fastlz.lua` 压缩并去掉 4 字节长度头，交给 C 版解压。

两个方向都能还原出原始数据即判定通过。

### 测试数据

- **随机样本数据**：`samples/` 下的 1000 个样本，由测试工具生成，覆盖不同长度与
  压缩率高低的多种数据模式；
- **Noita 游戏实际文件**：`real/` 下的 2933 个真实文件，共 139,039,716 字节
  （约 132.6 MiB），涵盖 `.bin`、`.png_petri`、`.xml`、`.csv`、`.wak`、`.bmp`、
  `.lua` 等多种类型，最大单文件 42 MB（`real/data/data.wak`）。

### 测试结果

**全部通过**（完整记录见 `real_test_report.txt`）：

| 指标 | 数值 |
| --- | --- |
| 文件总数 | 2933 |
| 已测数据量 | 139,039,716 字节（约 132.6 MiB） |
| 通过 | 2931 |
| 失败 | 0 |
| 跳过 | 2（0 字节的空占位文件，空输入无法进行有意义的压缩测试） |
| 耗时 | 约 10.8 秒 |

两个交叉方向、随机样本与真实游戏文件均无一失败。

> 关于压缩结果不完全一致：C 参考实现是 FastLZ 0.5.0，而本移植基于 lua-fastlz 打包的
> FastLZ 0.1.0，两者的哈希函数与边界常量不同，因此对同一输入压缩出的字节流通常并不
> 逐字节相同；但**压缩格式完全兼容**，交叉解压都能正确还原——这正是本测试要验证的目标。
>
> 测试过程中还发现并修复了 Lua 端在 level 2 下的一个边界越界读取问题（匹配延伸到输入
> 末尾时读取末尾之后的 1~2 个字节），修复方式为对越界字节以 `0` 顶替。

## 目录说明

| 路径 | 说明 |
| --- | --- |
| `fastlz.lua` | 纯 Lua 实现（本仓库主产物） |
| `build/` | FastLZ 0.5.0 官方 C 源码，可用于编译对比用的原生库 |
| `fastlz.dll` / `lua51.dll` | 64 位 C 参考库 / 随 Noita 提供的 Lua 5.1 运行时 |
| `FastLzInterop/` | 交叉测试工具（C#），详见其 [README](FastLzInterop/README.md) |
| `samples/` / `real/` | 随机样本 / 真实游戏文件测试数据 |
| `licenses/` | FastLZ 与 lua-fastlz 的许可证文本 |

## AI 辅助说明

本移植库（`fastlz.lua`）与配套的交叉测试工具、测试数据生成及测试报告均由 AI 辅助完成。
所有兼容性结论都来自可复现的交叉测试：随机样本与
Noita 游戏真实文件的双向结果记录在 `real_test_report.txt` 中，全部通过。
