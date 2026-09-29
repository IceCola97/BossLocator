# Boss 定位器

[English](README.en.md) | [简体中文](README.md)

> 本项目由 AI 辅助制作，详见 [AI 辅助制作](#ai-辅助制作)。

这是一个 Noita 模组，把本目录复制到 Noita 安装目录下的
`mods/boss_locator`（Lua 路径使用该文件夹名）。它会在 `files/config.lua` 中列出的
Boss 实体被加载时进行追踪，把最近一次观测到的位置存入当前世界的存档，并为当前
平行世界绘制屏幕标记（或屏幕边缘箭头）。

可以在模组设置页中逐项启用或禁用。设置页还会显示当前世界的 Boss 是已死亡、
不在该世界、正在被追踪，还是仅来自更早的一次观测。

设置页里还有一个 **“扫描存档以同步实际位置”** 按钮：它读取当前存档的实体区块，
把其中所有 Boss 的位置一次性写入本存档记录，因此启用模组前就在玩的旧存档也能
立刻显示全部 Boss 位置。详见 [旧存档兼容](#旧存档兼容扫描存档以同步位置)。

mod.xml 中声明了 `request_no_api_restrictions="1"`，因为读取存档文件需要 Lua 的
`io.*` / `os.*`。Noita 自带的示例 mod.xml 就是这么写的：
“If a mod requires access to the full lua api e.g. os.* io.* it has to request acesss
via 'request_no_api_restrictions="1"'.”
本模组只用它**读取**存档，从不写入或修改存档文件；如果你把该值改回 `"0"`，
扫描按钮会变为禁用并提示缺少该项权限，其余功能不受影响。

## 持久化模型

运行时观测通过 `GlobalsSetValue` 写入，属于当前世界存档的一部分。键名按 New Game+
次数、平行世界索引和 Boss id 进行命名空间划分。当引擎提供
`GetParallelWorldPosition` 时优先使用其结果，并以普通/NG+ 的世界宽度作为兼容性回退。
面向用户的复选框只是普通的运行时模组设置，与存档数据分开存放。

被追踪的实体会挂上一个轻量的 `script_death` 观察器，同时扫描器还会检查 HP 以及
适用的原版主世界死亡标记。对于只是直接消失的实体，会被视为所在区块被流式卸载。
其缓存位置会被保留，因此再次回到该区域时可以用已加载的实体替换它。已确认的死亡
对于该世界是粘性的，并会隐藏标记。这就是为什么模组在已观测实体被卸载后，绝不会
回退到某个默认坐标。

可重复生成的类型单独处理。两个平行世界的暗影 Boss 以及 Sauvojen tuntija（可由
Monstrous Powder 创造）只记录最近一次被击败的实例，而不会永久关闭该 Boss 类型。
因此之后出现的实例可以重新变为 `alive`，且当前每个已加载的实例都会获得各自的标记。
Epäalkemisti 不适用此规则：摧毁它的死亡之球即该世界的最终死亡。

Epäalkemisti（非炼金术士）被表示为一种感知复活的条目：其持续 220 帧的死亡之球阶段
被记为 `revive_pending`，而不是 `dead`。死亡之球被卸载时会保留该待复活状态与位置；
看到新的存活实体时状态会变回 `alive`，而在观测到死亡之球生命值为零时则记录为已确认
死亡。模组不会自行创建计时器。原版死亡之球使用一个每 220 帧调度一次的 LuaComponent，
并在死亡之球当前的 transform 位置重生 Boss。如果死亡之球被流式卸载，其实体数据与
transform 会随区块一起保存。之后重新加载时，无论 220 帧回调是继续还是立即触发，都以
原版组件为准；两种情况下，重生位置都是存档中的死亡之球位置，绝不会是凭空编造的默认值。

## Boss 定义

`files/config.lua` 包含 Boss 列表、文件名/标签匹配规则、世界策略、复活元数据，以及
可选的默认坐标。原版实体的文件名和标签可能随游戏版本变化，也可能被其他模组修改，
因此所有匹配规则集中放在一处。以文件名/名称匹配为主；当两个实体共用同一文件名时，
用标签作为额外校验。默认坐标在针对具体游戏数据版本验证之前有意留空；未被观测到的
Boss 不会显示在虚构的位置上。

其中一个条目在本次改动中按实际游戏数据修正：Alkemistin Varjo（炼金术士之影）原先
要求标签 `boss_parallel`，但原版实体数据里并不存在该标签，导致它既无法被运行时追踪、
也无法被存档扫描命中。现在改用平行世界专属实体本身来识别：
`data/entities/animals/parallel/alchemist/parallel_alchemist.xml`（名称
`$animal_parallel_alchemist`）。如果你的游戏版本里该实体不同，请修改
`files/config.lua` 中的这一项。

另外，Kolmisilmän Koipi 现在要求实体带 `boss` 标签：原版数据里
`boss_limbs_physics.xml`（它的物理体）和 `ending_placeholder/` 下的副本与它同名，
此前会被误判成同一个 Boss。

未填任何默认坐标，也从不修改任何存档。上文所述的扫描会以只读方式读取游戏正在
使用的存档；除此之外，状态从启用本模组并观测到相关区块时开始累积。

## 旧存档兼容：扫描存档以同步位置

模组原本只从“启用模组后观测到的区块”开始积累状态，因此对一个已经在玩的旧存档
一无所知。设置页中的 **“扫描存档以同步实际位置”** 按钮解决的正是这一点：它把
存档里已经存在的 Boss 位置一次性读出来并写入本存档记录。

### 使用方式

1. 进入游戏（载入一个存档）。未进入游戏时按钮会显示为禁用并提示“需要先进入
   游戏（载入一个存档）才能扫描存档”。
2. 打开 模组设置 → Boss Locator，点击“扫描存档以同步实际位置”。
3. 按钮右侧显示本次结果（存档槽、区块数、更新了多少个 Boss 位置、失败数），
   游戏内同时弹出通知；鼠标悬停在按钮上可看到详细报告（扫描的存档目录、实体数、
   命中的 Boss 名称等）。

“载入存档时自动同步一次”可以勾选（默认关闭），勾选后每次进入世界都会在加载完毕
约两秒后自动扫描一次，适合长期游玩同一个旧存档。

### 扫描做了什么

1. **定位存档目录**（`files/save_locator.lua`）。所有路径都由运行时得到，没有任何
   写死的盘符或用户名：
   - 候选根目录 = 当前游戏的**工作目录**（使用相对路径，因此指向正在运行的那份
     安装）＋ 操作系统报告的用户数据目录（Windows 的
     `%USERPROFILE%\AppData\LocalLow\Nolla_Games_Noita`、Linux 的
     `$XDG_DATA_HOME` 或 `$HOME/.local/share/Nolla_Games_Noita`、macOS 的
     `$HOME/Library/Application Support/Nolla_Games_Noita`）。
   - 存档槽（`save00`、`save01`…）同样不写死：优先采用**游戏本身报告的槽位**
     （WorldStateComponent 的本局统计文件路径 / 会话编号），否则采用**最近写入过的
     那个槽**（游戏会持续向正在游玩的槽写入区块），都没有时退回到 `save00`。
     因此“多存档”类模组把存档切到 `save01` 也能被正确识别。设置页里的
     “扫描的存档槽”可以手动指定，留空即为自动。
2. **枚举实体区块**（`files/save_fs.lua`）。跨平台：Windows 用 LuaJIT 的 `ffi`
   调用 `FindFirstFileA`，Linux/macOS 用 `io.popen` + `ls`。若两者都不可用，还会用
   `io.open` 逐个探测区块文件名（`entities_<区块索引>.bin`，索引 = 区块 x +
   区块 y × 2000，该关系已用真实存档核对过），因此扫描不依赖目录列表能力。
3. **解析实体**（`saves/save_scanner.lua` + `saves/entity_parser.lua`）。区块是 fastlz
   压缩的，模组内自带纯 Lua 的 `fastlz/fastlz.lua`（不需要任何 DLL）；解析器只读
   实体的基础数据（名称、实体文件路径、标签、坐标），组件负载一律跳过。
4. **匹配 Boss 并写入位置**。匹配使用与运行时同一份 `files/config.lua` 定义，但针对
   存档记录收紧为“实体文件名主干完全相同”或“实体名称完全相同”，并按逗号分隔的
   标签整体比较——存档里除了 Boss 本身还存着它的附属实体（例如
   `boss_centipede_minion.xml`、`orb_green_boss_dragon.xml`），子串匹配会把它们
   误判成 Boss。
5. 位置通过 `GlobalsSetValue` 写入当前存档，与运行时追踪使用同一套记录。状态为
   `dead`/`defeated` 的条目会被跳过（存活的 Boss 与尸体在存档的基础数据里无法
   区分，已确认的死亡不能被“复活”）；其余条目变为 `unloaded`（位置已知、当前是否
   加载未知），Epäalkemisti 的死亡之球则记为 `revive_pending`。存档里没有出现的
   Boss 不会被改动。

扫描是**分帧执行**的：每帧只处理一个切片（默认约 12 个区块或 96 KB），按钮旁会显示
“扫描中 x/y 个区块”，所以即使存档很大也不会让游戏长时间无响应。自动同步同样按帧
推进，不会拖慢载入世界。

### 限制

- 读到的是**最后一次存档时**的位置，不是实时位置；之后由运行时追踪刷新。
- 只读取，不写入：扫描过程不会修改任何存档文件，只写入本模组的 `Globals` 记录。
- 存档记录里没有组件数据，因此无法得知生命值，也不能判断某个 Boss 实体是活着的
  还是尸体；这就是“已确认死亡保持粘性”的原因。

## 验证

`tests/` 中包含用于验证持久化、平行世界选择、死亡回调、卸载处理以及复活状态转换
竞态的 Lua 5.1 测试。小型 C# 运行器加载 Noita 自带的 `lua51.dll`，使测试使用与游戏
相同的 Lua 版本。

与存档扫描相关的测试完全离线运行、不写任何文件：

- `tests/save_fs_test.lua`：真实文件系统层（平台探测、路径拼接、目录列举、
  修改时间、区块索引探测），以仓库自带的样例存档和仓库文件作为只读样本。
- `tests/save_locator_test.lua`：用内存文件系统描述多个根目录与多个存档槽，验证
  “最近写入优先”“游戏报告的槽位优先”“手动指定优先”“无目录列表时退化为区块索引
  探测”。
- `tests/save_sync_test.lua`：端到端扫描。测试用真实的二进制格式（大端实体体 +
  小端尺寸头 + fastlz 压缩）构造存档，断言命中/未命中的 Boss、平行世界索引、
  死亡粘性、跨 Lua 上下文的缓存失效、主菜单与受限 Lua 状态下的按钮禁用逻辑。
- `tests/lua_bit_test.lua`：纯 Lua 位运算回退与 LuaJIT 原生 `bit` 的一致性，以及
  同一 fastlz 压缩流在两者下的解压结果相同。
- `tests/config_match_test.lua`：把全部 21 个 Boss 定义与真实原版实体的
  名称/标签/路径（以及 16 个同名或同路径的“疑似”实体）逐一比对，保证每个定义都能
  命中且只命中它自己的实体，同时不会把附属实体或相似文件误判成 Boss。

在仓库根目录下运行整套测试（`tests/Lua51Runner.csproj` 加载 Noita 自带的
`saves/lua51.dll`，需要 .NET SDK）：

```powershell
dotnet run --project tests/Lua51Runner.csproj -- saves tests/syntax_test.lua tests/lua_bit_test.lua `
  tests/config_match_test.lua tests/state_test.lua tests/world_test.lua tests/locator_test.lua `
  tests/death_hook_test.lua tests/save_scanner_test.lua tests/save_fs_test.lua `
  tests/save_locator_test.lua tests/save_sync_test.lua
```

## AI 辅助制作

本项目在 AI 辅助下完成。AI 参与了 Lua 模组代码、测试套件与文档的
编写。所有关于引擎行为的假设都由 `tests/` 中的测试和游戏内验证支撑；凡未针对具体
游戏数据版本验证过的内容，都会有意留空而不是猜测。
