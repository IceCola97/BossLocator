--[[
  fastlz.lua —— FastLZ 压缩算法的纯 Lua 移植版

  移植自 lua-fastlz（https://github.com/oneoo/lua-fastlz）所打包的
  FastLZ C 实现（作者 Ariya Hidayat，MIT 许可证），数据格式与 C 版完全兼容：

    - 与 lua-fastlz 的 C 模块一样，压缩结果头部带 4 字节大端序（网络序）
      的原始数据长度，之后是原始 FastLZ 压缩流。
    - 压缩：输入 < 65536 字节使用 level 1，否则使用 level 2（同 C 版）。
    - 解压：根据流首字节自动识别 level 1 / level 2，
      因此可以解压原版 C 模块（fastlz_compress）产出的数据，反之亦然。

  用法：
    local fastlz = require("fastlz")
    local c = fastlz.compress(data)      -- 失败返回 nil
    local d = fastlz.decompress(c)       -- 失败返回 nil

  兼容 Lua 5.1 / 5.2 / 5.3 / 5.4 及 LuaJIT（自动选择位运算实现）。

  FastLZ 原始版权声明：
  Copyright (C) 2005-2007 Ariya Hidayat — MIT License
]]

local fastlz = {}

----------------------------------------------------------------------
-- 位运算兼容层
----------------------------------------------------------------------
local band, bor, bxor, lshift, rshift

if _VERSION == "Lua 5.3" or _VERSION == "Lua 5.4" then
    -- 5.3+ 原生位运算（用 load 避免在低版本解释器下产生语法错误）
    band   = load("return function(a, b) return a & b end")()
    bor    = load("return function(a, b) return a | b end")()
    bxor   = load("return function(a, b) return a ~ b end")()
    lshift = load("return function(a, b) return a << b end")()
    rshift = load("return function(a, b) return a >> b end")()
else
    local bit
    if _VERSION == "Lua 5.2" then
        bit = bit32
    else
        local ok
        ok, bit = pcall(require, "bit")        -- LuaJIT 自带
        if not ok then ok, bit = pcall(require, "bit32") end
        if not ok then
            error("fastlz.lua: Lua 5.1 环境需要 bit 库（LuaJIT 自带，或安装 luabitop）")
        end
    end
    band, bor, bxor = bit.band, bit.bor, bit.bxor
    lshift, rshift = bit.lshift, bit.rshift
end

----------------------------------------------------------------------
-- 常量与工具
----------------------------------------------------------------------
local byte  = string.byte
local char  = string.char
local sub   = string.sub
local concat = table.concat
local unpack = table.unpack or unpack  -- 5.1/5.2 兼容

local MAX_COPY = 32
local MAX_LEN  = 264
local HASH_LOG  = 13
local HASH_SIZE = 8192          -- 1 << 13
local HASH_MASK = 8191          -- HASH_SIZE - 1

-- LuaJIT 下用 table.create 预分配哈希表
local table_create = table.create

local function new_htab()
    local t
    if table_create then t = table_create(HASH_SIZE, 0) else t = {} end
    for i = 0, HASH_SIZE - 1 do t[i] = 1 end
    return t
end

-- 哈希函数：对应 C 的 HASH_FUNCTION（v 恒小于 2^16，位移安全）
local function hash3(b0, b1, b2)
    local v = b0 + b1 * 256
    return band(bxor(v, bxor(b1 + b2 * 256, rshift(v, 16 - HASH_LOG))), HASH_MASK)
end

-- 字节数组（table）转字符串，分块避免 string.char 参数过多
local function bytes_to_string(t, n)
    if n == 0 then return "" end
    local parts = {}
    local p = 0
    local i = 1
    while i <= n do
        local j = i + 1023
        if j > n then j = n end
        p = p + 1
        parts[p] = char(unpack(t, i, j))
        i = j + 1
    end
    return concat(parts)
end

----------------------------------------------------------------------
-- 压缩核心（同时实现 level 1 与 level 2，逐行对应 C 版 fastlz.c）
----------------------------------------------------------------------
local function compress_level(level, input)
    local length = #input

    -- C: if (length < 4) —— 仅字面量拷贝
    if length < 4 then
        if length > 0 then
            return char(length - 1) .. input
        end
        return ""
    end

    local MAX_DISTANCE     = (level == 1) and 8192 or 8191
    local MAX_FARDISTANCE  = 73725  -- 65535 + 8191 - 1（仅 level 2）

    local out  = {}   -- 输出片段（字符串）列表
    local outn = 0

    local htab = new_htab()

    -- 指针约定：Lua 索引 = C 指针偏移 + 1
    local ip       = 3            -- 前两字节已作为字面量输出
    local ip_bound = length - 1   -- C: ip + length - 2
    local ip_limit = length - 11  -- C: ip + length - 12

    -- 惰性字面量缓冲：placeholder 控制字节 + 输入区间 [lit_start, ...]
    local copy = 2
    local lit_start = 1
    out[1] = char(MAX_COPY - 1)
    outn = 1
    local pending_ctrl = 1

    while ip < ip_limit do
        local ref
        local distance
        local len = 3
        local anchor = ip
        local matched = false

        -- level 2：优先检测连续重复字节（run）
        if level == 2 then
            local b_im1 = byte(input, ip - 1)
            local b_i   = byte(input, ip)
            if b_i == b_im1
               and b_im1 == byte(input, ip + 1)
               and b_i   == byte(input, ip + 2) then
                distance = 1
                ip = ip + 3
                ref = anchor + 2
                matched = true
            end
        end

        if not matched then
            -- 哈希查找潜在匹配
            local b0 = byte(input, ip)
            local b1 = byte(input, ip + 1)
            local b2 = byte(input, ip + 2)
            local hval = hash3(b0, b1, b2)
            ref = htab[hval]
            distance = anchor - ref
            htab[hval] = anchor

            -- 检查前 3 字节是否匹配
            if distance == 0
               or distance >= ((level == 1) and MAX_DISTANCE or MAX_FARDISTANCE)
               or byte(input, ref)     ~= b0
               or byte(input, ref + 1) ~= b1
               or byte(input, ref + 2) ~= b2 then
                matched = false
            else
                ref = ref + 3
                ip  = ip + 3
                if level == 2 and distance >= MAX_DISTANCE then
                    -- 远距离匹配至少要求 5 字节
                    if byte(input, ip)     ~= byte(input, ref)
                       or byte(input, ip + 1) ~= byte(input, ref + 1) then
                        matched = false
                    else
                        ip  = ip + 2
                        ref = ref + 2
                        len = len + 2
                        matched = true
                    end
                else
                    matched = true
                end
            end
        end

        if matched then
            ------------------------------------------------ match:
            ip = anchor + len
            distance = distance - 1

            if distance == 0 then
                -- 零距离表示连续重复（run）
                local x = byte(input, ip - 1)
                while ip < ip_bound do
                    if byte(input, ref) ~= x then
                        ref = ref + 1
                        break
                    end
                    ref = ref + 1
                    ip  = ip + 1
                end
            else
                -- 扩展匹配长度（对应 C 的 8 路展开 + 收尾循环）
                while true do
                    if byte(input, ref) ~= byte(input, ip) then ref = ref + 1; ip = ip + 1; break end
                    ref = ref + 1; ip = ip + 1
                    if byte(input, ref) ~= byte(input, ip) then ref = ref + 1; ip = ip + 1; break end
                    ref = ref + 1; ip = ip + 1
                    if byte(input, ref) ~= byte(input, ip) then ref = ref + 1; ip = ip + 1; break end
                    ref = ref + 1; ip = ip + 1
                    if byte(input, ref) ~= byte(input, ip) then ref = ref + 1; ip = ip + 1; break end
                    ref = ref + 1; ip = ip + 1
                    if byte(input, ref) ~= byte(input, ip) then ref = ref + 1; ip = ip + 1; break end
                    ref = ref + 1; ip = ip + 1
                    if byte(input, ref) ~= byte(input, ip) then ref = ref + 1; ip = ip + 1; break end
                    ref = ref + 1; ip = ip + 1
                    if byte(input, ref) ~= byte(input, ip) then ref = ref + 1; ip = ip + 1; break end
                    ref = ref + 1; ip = ip + 1
                    if byte(input, ref) ~= byte(input, ip) then ref = ref + 1; ip = ip + 1; break end
                    ref = ref + 1; ip = ip + 1
                    while ip < ip_bound do
                        if byte(input, ref) ~= byte(input, ip) then
                            ref = ref + 1
                            ip  = ip + 1
                            break
                        end
                        ref = ref + 1
                        ip  = ip + 1
                    end
                    break
                end
            end

            -- 冲刷待处理的字面量（C: if (copy) *(op-copy-1)=copy-1; else op--;）
            if copy > 0 then
                out[pending_ctrl] = char(copy - 1)
                outn = outn + 1
                out[outn] = sub(input, lit_start, lit_start + copy - 1)
            end
            copy = 0

            ip  = ip - 3
            len = ip - anchor

            -- 编码匹配
            if level == 2 then
                if distance < MAX_DISTANCE then
                    if len < 7 then
                        outn = outn + 1; out[outn] = char(lshift(len, 5) + rshift(distance, 8))
                        outn = outn + 1; out[outn] = char(band(distance, 255))
                    else
                        outn = outn + 1; out[outn] = char(lshift(7, 5) + rshift(distance, 8))
                        local l = len - 7
                        while l >= 255 do
                            outn = outn + 1; out[outn] = char(255)
                            l = l - 255
                        end
                        outn = outn + 1; out[outn] = char(l)
                        outn = outn + 1; out[outn] = char(band(distance, 255))
                    end
                else
                    distance = distance - MAX_DISTANCE
                    if len < 7 then
                        outn = outn + 1; out[outn] = char(lshift(len, 5) + 31)
                        outn = outn + 1; out[outn] = char(255)
                        outn = outn + 1; out[outn] = char(rshift(distance, 8))
                        outn = outn + 1; out[outn] = char(band(distance, 255))
                    else
                        outn = outn + 1; out[outn] = char(lshift(7, 5) + 31)
                        local l = len - 7
                        while l >= 255 do
                            outn = outn + 1; out[outn] = char(255)
                            l = l - 255
                        end
                        outn = outn + 1; out[outn] = char(l)
                        outn = outn + 1; out[outn] = char(255)
                        outn = outn + 1; out[outn] = char(rshift(distance, 8))
                        outn = outn + 1; out[outn] = char(band(distance, 255))
                    end
                end
            else
                -- level 1
                if len > MAX_LEN - 2 then
                    while len > MAX_LEN - 2 do
                        outn = outn + 1; out[outn] = char(lshift(7, 5) + rshift(distance, 8))
                        outn = outn + 1; out[outn] = char(MAX_LEN - 2 - 7 - 2)
                        outn = outn + 1; out[outn] = char(band(distance, 255))
                        len = len - (MAX_LEN - 2)
                    end
                end
                if len < 7 then
                    outn = outn + 1; out[outn] = char(lshift(len, 5) + rshift(distance, 8))
                    outn = outn + 1; out[outn] = char(band(distance, 255))
                else
                    outn = outn + 1; out[outn] = char(lshift(7, 5) + rshift(distance, 8))
                    outn = outn + 1; out[outn] = char(len - 7)
                    outn = outn + 1; out[outn] = char(band(distance, 255))
                end
            end

            -- 在匹配边界处更新哈希表
            -- 注意：当匹配一直延伸到输入末尾时，C 版会读取末尾之后的 1~2 个字节
            -- （依赖调用方缓冲区预留的富余空间，属于 FastLZ 的既有行为）。
            -- 纯 Lua 的 string.byte 越界会返回 nil，这里用 0 顶替。
            -- 该哈希表项在末尾处之后不会再被使用，因此不会影响压缩结果。
            local c0 = byte(input, ip)     or 0
            local c1 = byte(input, ip + 1) or 0
            local c2 = byte(input, ip + 2) or 0
            htab[hash3(c0, c1, c2)] = ip
            ip = ip + 1
            c0 = byte(input, ip)     or 0
            c1 = byte(input, ip + 1) or 0
            c2 = byte(input, ip + 2) or 0
            htab[hash3(c0, c1, c2)] = ip
            ip = ip + 1

            -- C 版此处预写一个字面量控制字节（惰性实现：留到下一个字面量出现时再写）
        else
            ------------------------------------------------ literal:
            if copy == 0 then
                outn = outn + 1
                out[outn] = char(MAX_COPY - 1)  -- placeholder，之后可能被修正
                pending_ctrl = outn
                lit_start = anchor
            end
            copy = copy + 1
            ip = anchor + 1
            if copy == MAX_COPY then
                -- 满 32 字节：placeholder 的值恰好正确，直接冲刷
                outn = outn + 1
                out[outn] = sub(input, lit_start, lit_start + copy - 1)
                copy = 0
                pending_ctrl = nil
            end
        end
    end

    -- 剩余数据作为字面量拷贝
    ip_bound = ip_bound + 1  -- C: ip_bound++（此时 ip_bound == length）
    while ip <= ip_bound do
        if copy == 0 then
            outn = outn + 1
            out[outn] = char(MAX_COPY - 1)
            pending_ctrl = outn
            lit_start = ip
        end
        copy = copy + 1
        ip = ip + 1
        if copy == MAX_COPY then
            outn = outn + 1
            out[outn] = sub(input, lit_start, lit_start + copy - 1)
            copy = 0
            pending_ctrl = nil
        end
    end

    -- 修正最后一段字面量的长度（C: if (copy) ... else op--;）
    if copy > 0 then
        out[pending_ctrl] = char(copy - 1)
        outn = outn + 1
        out[outn] = sub(input, lit_start, lit_start + copy - 1)
    end

    -- level 2 标记：首字节置第 5 位（该字节为字面量控制字节，第 5 位必为 0）
    if level == 2 then
        out[1] = char(byte(out[1], 1) + 32)
    end

    return concat(out)
end

----------------------------------------------------------------------
-- 解压核心（对应 C 版 fastlz_decompress，含 FASTLZ_SAFE 边界检查）
----------------------------------------------------------------------
local function decompress_core(level, input, maxout)
    local length = #input
    local MAX_DISTANCE = (level == 1) and 8192 or 8191

    local out  = {}   -- 输出字节表（匹配拷贝需要随机访问已输出内容）
    local outn = 0
    local ip = 1

    local ctrl = band(byte(input, ip), 31)
    ip = ip + 1
    local loop = true

    while loop do
        local ref = outn + 1         -- 对应 C 的 op（1 基索引）
        local len = rshift(ctrl, 5)
        local ofs = lshift(band(ctrl, 31), 8)

        if ctrl >= 32 then
            ---------------- 匹配拷贝 ----------------
            len = len - 1
            ref = ref - ofs

            if level == 1 then
                if len == 6 then  -- 7 - 1
                    len = len + byte(input, ip); ip = ip + 1
                end
                ref = ref - byte(input, ip); ip = ip + 1
            else
                local code
                if len == 6 then
                    repeat
                        code = byte(input, ip); ip = ip + 1
                        len = len + code
                    until code ~= 255
                end
                code = byte(input, ip); ip = ip + 1
                ref = ref - code

                -- 16 位远距离匹配
                if code == 255 and ofs == 7936 then  -- 31 << 8
                    ofs = lshift(byte(input, ip), 8); ip = ip + 1
                    ofs = ofs + byte(input, ip);      ip = ip + 1
                    ref = outn + 1 - ofs - MAX_DISTANCE
                end
            end

            -- FASTLZ_SAFE 边界检查
            if outn + len + 3 > maxout then return nil end
            if ref < 2 then return nil end

            if ip <= length then
                ctrl = byte(input, ip); ip = ip + 1
            else
                loop = false
            end

            if ref == outn + 1 then
                -- 连续重复（run）优化路径
                local b = out[ref - 1]
                for _ = 1, len + 3 do
                    outn = outn + 1
                    out[outn] = b
                end
            else
                ref = ref - 1
                for _ = 1, len + 3 do
                    outn = outn + 1
                    out[outn] = out[ref]
                    ref = ref + 1
                end
            end
        else
            ---------------- 字面量拷贝 ----------------
            local n = ctrl + 1
            if outn + n > maxout then return nil end
            if ip + n - 1 > length then return nil end
            for _ = 1, n do
                outn = outn + 1
                out[outn] = byte(input, ip)
                ip = ip + 1
            end
            loop = ip <= length
            if loop then
                ctrl = byte(input, ip); ip = ip + 1
            end
        end
    end

    return bytes_to_string(out, outn)
end

-- 带错误保护：输入数据损坏时返回 nil（等价于 C 版返回 0）
local function decompress_level(level, input, maxout)
    local ok, res = pcall(decompress_core, level, input, maxout)
    if not ok then return nil end
    return res
end

----------------------------------------------------------------------
-- 对外 API（与 lua-fastlz C 模块的数据格式一致：4 字节大端长度头 + FastLZ 流）
----------------------------------------------------------------------

--- 压缩字符串，返回压缩后的字符串；失败返回 nil。
-- 数据格式：<4 字节大端原始长度><fastlz 压缩流>，与 C 模块 fastlz_compress 一致。
function fastlz.compress(data)
    if type(data) ~= "string" then return nil end
    local length = #data
    if length < 1 then return nil end
    -- C 版在输入 < 65536 时使用 level 1，否则 level 2
    local body
    if length < 65536 then
        body = compress_level(1, data)
    else
        body = compress_level(2, data)
    end
    -- 4 字节大端序长度头（对应 C 版的 htonl(vlen)）
    local header = char(
        band(rshift(length, 24), 255),
        band(rshift(length, 16), 255),
        band(rshift(length, 8), 255),
        band(length, 255)
    )
    return header .. body
end

--- 解压字符串，返回原始字符串；数据损坏或格式非法时返回 nil。
-- 兼容 C 模块 fastlz_decompress：读取 4 字节大端长度头，再解压 FastLZ 流。
function fastlz.decompress(data)
    if type(data) ~= "string" then return nil end
    if #data < 5 then return nil end

    local b1, b2, b3, b4 = byte(data, 1, 4)
    local value_len = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
    if value_len < 1 then return nil end

    local body = sub(data, 5)
    if #body < 1 then return nil end

    -- 压缩级别标识在流首字节的高 3 位
    local level = rshift(byte(body, 1), 5) + 1
    if level ~= 1 and level ~= 2 then return nil end

    local result = decompress_level(level, body, value_len + 20)
    if not result then return nil end
    if #result < value_len then return nil end  -- 数据损坏

    return sub(result, 1, value_len)
end

-- 兼容原名（lua-fastlz C 模块注册的全局函数名）
fastlz.fastlz_compress   = fastlz.compress
fastlz.fastlz_decompress = fastlz.decompress

return fastlz
