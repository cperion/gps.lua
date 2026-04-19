local bit = require("bit")
local sdl3 = require("ui._sdl3")
local ffi = sdl3.ffi
local sdl = sdl3.sdl
local ttf = sdl3.ttf
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Layout = T.Layout

local M = {}

local function ensure_init()
    sdl3.ensure_ttf()
end

local function err(prefix)
    local msg = sdl.SDL_GetError()
    if msg == nil then
        error(prefix, 2)
    end
    error(prefix .. ": " .. ffi.string(msg), 2)
end

local function finite(n)
    return n ~= nil and n < math.huge
end

local function round(n)
    if n >= 0 then return math.floor(n + 0.5) end
    return math.ceil(n - 0.5)
end

local function read_text_bytes(text, offset, length)
    if text == nil then return "" end
    if offset < 0 then offset = 0 end
    if length < 0 then return string.sub(text, offset + 1) end
    if length == 0 then return "" end
    return string.sub(text, offset + 1, offset + length)
end

local function normalize_align(align)
    if align == 1 then return ffi.C.TTF_HORIZONTAL_ALIGN_CENTER end
    if align == 2 then return ffi.C.TTF_HORIZONTAL_ALIGN_RIGHT end
    return ffi.C.TTF_HORIZONTAL_ALIGN_LEFT
end

local function normalize_direction(direction)
    if direction == nil then return nil end
    if direction == ffi.C.TTF_DIRECTION_LTR or direction == 4 or direction == "ltr" or direction == "LTR" then
        return ffi.C.TTF_DIRECTION_LTR
    end
    if direction == ffi.C.TTF_DIRECTION_RTL or direction == 5 or direction == "rtl" or direction == "RTL" then
        return ffi.C.TTF_DIRECTION_RTL
    end
    if direction == ffi.C.TTF_DIRECTION_TTB or direction == 6 or direction == "ttb" or direction == "TTB" then
        return ffi.C.TTF_DIRECTION_TTB
    end
    if direction == ffi.C.TTF_DIRECTION_BTT or direction == 7 or direction == "btt" or direction == "BTT" then
        return ffi.C.TTF_DIRECTION_BTT
    end
    return ffi.C.TTF_DIRECTION_INVALID
end

local function layout_flow(direction)
    if direction == ffi.C.TTF_DIRECTION_LTR then return Layout.FlowLTR end
    if direction == ffi.C.TTF_DIRECTION_RTL then return Layout.FlowRTL end
    if direction == ffi.C.TTF_DIRECTION_TTB then return Layout.FlowTTB end
    if direction == ffi.C.TTF_DIRECTION_BTT then return Layout.FlowBTT end
    return Layout.FlowUnknown
end

local function normalize_script(script)
    if script == nil then return nil end
    if type(script) == "number" then return script end
    if type(script) == "string" then
        if #script == 4 then
            return tonumber(ttf.TTF_StringToTag(script))
        end
    end
    return nil
end

local function default_font_path()
    local candidates = {
        "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf",
        "/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
        "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
    }
    for i = 1, #candidates do
        local f = io.open(candidates[i], "rb")
        if f ~= nil then
            f:close()
            return candidates[i]
        end
    end
    return nil
end

local function normalize_font_spec(spec, default_path)
    if type(spec) == "string" then
        return { path = spec }
    end
    if type(spec) == "table" then
        return spec
    end
    if spec == nil and default_path ~= nil then
        return { path = default_path }
    end
    return nil
end

function M.new(opts)
    ensure_init()

    opts = opts or {}
    local provided_fonts = opts.fonts or {}
    local resolve_font = opts.resolve_font
    local default_font = opts.default_font or default_font_path()
    local default_direction = normalize_direction(opts.direction)
    local default_script = normalize_script(opts.script)
    local default_language = opts.language
    local default_wrap_whitespace_visible = opts.wrap_whitespace_visible == true
    local font_cache = {}
    local closed = false

    local self = {}

    local function font_spec_for(style)
        local spec
        if resolve_font ~= nil then
            spec = resolve_font(style.font_id, style)
        else
            spec = provided_fonts[style.font_id]
        end
        spec = normalize_font_spec(spec, default_font)
        if spec == nil or spec.path == nil then
            error("ui.text_sdl3: no font path for font_id=" .. tostring(style.font_id), 3)
        end
        return spec
    end

    local function font_cache_key(path, size)
        return path .. "\0" .. tostring(size)
    end

    local function configure_font(font, style, spec)
        ttf.TTF_SetFontWrapAlignment(font, normalize_align(style.align))

        local language = spec.language
        if language == nil then language = default_language end
        if not ttf.TTF_SetFontLanguage(font, language) then
            err("ui.text_sdl3: TTF_SetFontLanguage failed")
        end

        local direction = normalize_direction(spec.direction)
        if direction == nil then direction = default_direction end
        if direction == nil then direction = ffi.C.TTF_DIRECTION_INVALID end
        if not ttf.TTF_SetFontDirection(font, direction) then
            err("ui.text_sdl3: TTF_SetFontDirection failed")
        end

        local script = normalize_script(spec.script)
        if script == nil then script = default_script end
        if script == nil then script = 0 end
        if not ttf.TTF_SetFontScript(font, script) then
            err("ui.text_sdl3: TTF_SetFontScript failed")
        end
    end

    local function get_font(style, spec, seen)
        local key = font_cache_key(spec.path, style.font_size)
        local cached = font_cache[key]
        if cached ~= nil then
            configure_font(cached, style, spec)
            return cached
        end

        local font = ttf.TTF_OpenFont(spec.path, style.font_size)
        if font == nil then
            err("ui.text_sdl3: TTF_OpenFont failed for " .. tostring(spec.path))
        end

        font_cache[key] = font
        configure_font(font, style, spec)

        seen = seen or {}
        seen[spec.path] = true
        local fallbacks = spec.fallbacks
        if fallbacks ~= nil then
            for i = 1, #fallbacks do
                local fb = fallbacks[i]
                local fb_spec
                if type(fb) == "number" then
                    local lookup = resolve_font and resolve_font(fb, style) or provided_fonts[fb]
                    fb_spec = normalize_font_spec(lookup, nil)
                else
                    fb_spec = normalize_font_spec(fb, nil)
                end
                if fb_spec ~= nil and fb_spec.path ~= nil and not seen[fb_spec.path] then
                    seen[fb_spec.path] = true
                    local fb_font = get_font(style, fb_spec, seen)
                    if not ttf.TTF_AddFallbackFont(font, fb_font) then
                        err("ui.text_sdl3: TTF_AddFallbackFont failed")
                    end
                end
            end
        end

        return font
    end

    local function build_text(style, constraint)
        if closed then
            error("ui.text_sdl3: system is closed", 3)
        end

        local spec = font_spec_for(style)
        local font = get_font(style, spec)
        local content = style.content or ""
        local text = ttf.TTF_CreateText(nil, font, content, #content)
        if text == nil then
            err("ui.text_sdl3: TTF_CreateText failed")
        end

        local wrap_width = 0
        if finite(constraint.max_w) and constraint.max_w > 0 then
            wrap_width = round(constraint.max_w)
        end
        if not ttf.TTF_SetTextWrapWidth(text, wrap_width) then
            ttf.TTF_DestroyText(text)
            err("ui.text_sdl3: TTF_SetTextWrapWidth failed")
        end

        if not ttf.TTF_SetTextWrapWhitespaceVisible(text, default_wrap_whitespace_visible) then
            ttf.TTF_DestroyText(text)
            err("ui.text_sdl3: TTF_SetTextWrapWhitespaceVisible failed")
        end

        local direction = normalize_direction(spec.text_direction or spec.direction) or default_direction
        if direction ~= nil and direction ~= ffi.C.TTF_DIRECTION_INVALID then
            if not ttf.TTF_SetTextDirection(text, direction) then
                ttf.TTF_DestroyText(text)
                err("ui.text_sdl3: TTF_SetTextDirection failed")
            end
        end

        local script = normalize_script(spec.text_script or spec.script) or default_script
        if script ~= nil and script ~= 0 then
            if not ttf.TTF_SetTextScript(text, script) then
                ttf.TTF_DestroyText(text)
                err("ui.text_sdl3: TTF_SetTextScript failed")
            end
        end

        if not ttf.TTF_UpdateText(text) then
            ttf.TTF_DestroyText(text)
            err("ui.text_sdl3: TTF_UpdateText failed")
        end

        return text, font, spec
    end

    local function string_size(font, text_bytes)
        local w = ffi.new("int[1]")
        local h = ffi.new("int[1]")
        if not ttf.TTF_GetStringSize(font, text_bytes, #text_bytes, w, h) then
            err("ui.text_sdl3: TTF_GetStringSize failed")
        end
        return tonumber(w[0]), tonumber(h[0])
    end

    local function collect_lines(text, font, style)
        local lines = {}
        local line_count = tonumber(text.num_lines)
        local ascent = tonumber(ttf.TTF_GetFontAscent(font))
        local line_skip = tonumber(ttf.TTF_GetFontLineSkip(font))
        if line_skip <= 0 then
            line_skip = tonumber(ttf.TTF_GetFontHeight(font))
        end
        if line_count <= 0 then
            lines[1] = {
                x = 0,
                y = 0,
                w = 0,
                h = line_skip,
                baseline = ascent,
                byte_start = 0,
                byte_end = 0,
                text = "",
                runs = {
                    {
                        x = 0,
                        y = 0,
                        w = 0,
                        h = line_skip,
                        baseline = ascent,
                        byte_start = 0,
                        byte_end = 0,
                        font_id = style.font_id,
                        font_size = style.font_size,
                        font_weight = style.font_weight,
                        fg = style.fg,
                        text = "",
                        glyphs = {},
                    },
                },
            }
            return lines
        end

        local tmp = ffi.new("TTF_SubString[1]")
        for i = 0, line_count - 1 do
            if not ttf.TTF_GetTextSubStringForLine(text, i, tmp) then
                err("ui.text_sdl3: TTF_GetTextSubStringForLine failed")
            end
            local sub = tmp[0]
            local x = tonumber(sub.rect.x)
            local y = tonumber(sub.rect.y)
            local h = tonumber(sub.rect.h)
            if h <= 0 then h = line_skip end
            local byte_start = tonumber(sub.offset)
            local byte_end = byte_start + tonumber(sub.length)
            local line_text = read_text_bytes(style.content or "", byte_start, tonumber(sub.length))
            local w = string_size(font, line_text)
            lines[#lines + 1] = {
                x = x,
                y = y,
                w = w,
                h = h,
                baseline = ascent,
                byte_start = byte_start,
                byte_end = byte_end,
                text = line_text,
                runs = {
                    {
                        x = 0,
                        y = 0,
                        w = w,
                        h = h,
                        baseline = ascent,
                        byte_start = byte_start,
                        byte_end = byte_end,
                        font_id = style.font_id,
                        font_size = style.font_size,
                        font_weight = style.font_weight,
                        fg = style.fg,
                        text = line_text,
                        glyphs = {},
                    },
                },
            }
        end
        return lines
    end

    local function substring_flags(sub)
        local flags = tonumber(sub.flags)
        return flags,
            bit.band(flags, 0x00000100) ~= 0,
            bit.band(flags, 0x00000200) ~= 0,
            bit.band(flags, 0x00000400) ~= 0,
            bit.band(flags, 0x00000800) ~= 0
    end

    local function substring_to_cluster(sub)
        local flags = substring_flags(sub)
        return {
            flow = layout_flow(bit.band(flags, 0xFF)),
            cluster_index = tonumber(sub.cluster_index) + 1,
            line_index = tonumber(sub.line_index) + 1,
            byte_start = tonumber(sub.offset),
            byte_end = tonumber(sub.offset + sub.length),
            x = tonumber(sub.rect.x),
            y = tonumber(sub.rect.y),
            w = tonumber(sub.rect.w),
            h = tonumber(sub.rect.h),
        }
    end

    local function boundary_record(sub, byte_offset, x, text_start, line_start, line_end, text_end)
        local flags = tonumber(sub.flags)
        return {
            flow = layout_flow(bit.band(flags, 0xFF)),
            line_index = tonumber(sub.line_index) + 1,
            byte_offset = byte_offset,
            x = x,
            y = tonumber(sub.rect.y),
            w = tonumber(sub.rect.w),
            h = tonumber(sub.rect.h),
            text_start = text_start,
            line_start = line_start,
            line_end = line_end,
            text_end = text_end,
        }
    end

    local function substring_to_probe(sub)
        local flags, text_start, line_start, line_end, text_end = substring_flags(sub)
        return {
            flow = layout_flow(bit.band(flags, 0xFF)),
            cluster_index = tonumber(sub.cluster_index) + 1,
            line_index = tonumber(sub.line_index) + 1,
            byte_start = tonumber(sub.offset),
            byte_end = tonumber(sub.offset + sub.length),
            x = tonumber(sub.rect.x),
            y = tonumber(sub.rect.y),
            w = tonumber(sub.rect.w),
            h = tonumber(sub.rect.h),
            text_start = text_start,
            line_start = line_start,
            line_end = line_end,
            text_end = text_end,
        }
    end

    local function collect_text_records(text)
        local clusters = {}
        local boundaries = {}
        local cur = ffi.new("TTF_SubString[1]")
        if not ttf.TTF_GetTextSubString(text, 0, cur) then
            err("ui.text_sdl3: TTF_GetTextSubString failed")
        end

        while true do
            local sub = cur[0]
            local flags, text_start, line_start, line_end, text_end = substring_flags(sub)
            local flow = layout_flow(bit.band(flags, 0xFF))
            local x = tonumber(sub.rect.x)
            local w = tonumber(sub.rect.w)
            local start_x = x
            local end_x = x + w
            if flow == Layout.FlowRTL then
                start_x = x + w
                end_x = x
            end

            if tonumber(sub.length) > 0 then
                boundaries[#boundaries + 1] = boundary_record(sub, tonumber(sub.offset), start_x, text_start, line_start, false, false)
                clusters[#clusters + 1] = substring_to_cluster(sub)
                boundaries[#boundaries + 1] = boundary_record(sub, tonumber(sub.offset + sub.length), end_x, false, false, line_end, text_end)
            else
                boundaries[#boundaries + 1] = boundary_record(sub, tonumber(sub.offset), start_x, text_start, line_start, line_end, text_end)
            end

            if text_end then break end

            local nxt = ffi.new("TTF_SubString[1]")
            if not ttf.TTF_GetNextTextSubString(text, cur, nxt) then
                err("ui.text_sdl3: TTF_GetNextTextSubString failed")
            end
            cur[0] = nxt[0]
        end

        return clusters, boundaries
    end

    local function adjust_boundary_positions(font, lines, boundaries)
        for i = 1, #boundaries do
            local b = boundaries[i]
            local line = lines[b.line_index]
            if line ~= nil and b.flow ~= Layout.FlowRTL then
                local prefix_len = b.byte_offset - line.byte_start
                if prefix_len < 0 then prefix_len = 0 end
                if prefix_len > #line.text then prefix_len = #line.text end
                local prefix = string.sub(line.text, 1, prefix_len)
                local prefix_w = string_size(font, prefix)
                boundaries[i] = {
                    flow = b.flow,
                    line_index = b.line_index,
                    byte_offset = b.byte_offset,
                    x = line.x + prefix_w,
                    y = b.y,
                    w = b.w,
                    h = b.h,
                    text_start = b.text_start,
                    line_start = b.line_start,
                    line_end = b.line_end,
                    text_end = b.text_end,
                }
            end
        end
        return boundaries
    end

    local function measure_impl(style, constraint)
        local text, font = build_text(style, constraint)
        local w = ffi.new("int[1]")
        local h = ffi.new("int[1]")
        if not ttf.TTF_GetTextSize(text, w, h) then
            ttf.TTF_DestroyText(text)
            err("ui.text_sdl3: TTF_GetTextSize failed")
        end

        local lines = collect_lines(text, font, style)
        local clusters, boundaries
        if (style.content or "") ~= "" then
            clusters, boundaries = collect_text_records(text)
            boundaries = adjust_boundary_positions(font, lines, boundaries)
        end
        local result = {
            measured_w = tonumber(w[0]),
            measured_h = tonumber(h[0]),
            baseline = tonumber(ttf.TTF_GetFontAscent(font)),
            lines = lines,
            clusters = clusters,
            boundaries = boundaries,
        }

        ttf.TTF_DestroyText(text)
        return result
    end

    self.measure = measure_impl

    self.hit_test = function(style, constraint, x, y)
        if (style.content or "") == "" then
            return {
                flow = Layout.FlowUnknown,
                cluster_index = 1,
                line_index = 1,
                byte_start = 0,
                byte_end = 0,
                x = 0,
                y = 0,
                w = 0,
                h = tonumber(ttf.TTF_GetFontLineSkip(get_font(style, font_spec_for(style)))) or style.leading or style.font_size,
                text_start = true,
                line_start = true,
                line_end = true,
                text_end = true,
            }
        end
        local text = build_text(style, constraint)
        local tmp = ffi.new("TTF_SubString[1]")
        local ok = ttf.TTF_GetTextSubStringForPoint(text, round(x), round(y), tmp)
        if not ok then
            ttf.TTF_DestroyText(text)
            err("ui.text_sdl3: TTF_GetTextSubStringForPoint failed")
        end
        local out = substring_to_probe(tmp[0])
        ttf.TTF_DestroyText(text)
        return out
    end

    self.range_query = function(style, constraint, offset, length)
        if (style.content or "") == "" then
            return {}
        end
        local text = build_text(style, constraint)
        local count = ffi.new("int[1]")
        local arr = ttf.TTF_GetTextSubStringsForRange(text, offset or 0, length or -1, count)
        if arr == nil then
            ttf.TTF_DestroyText(text)
            err("ui.text_sdl3: TTF_GetTextSubStringsForRange failed")
        end

        local out = {}
        for i = 0, count[0] - 1 do
            out[#out + 1] = substring_to_probe(arr[i][0])
        end
        sdl.SDL_free(arr)
        ttf.TTF_DestroyText(text)
        return out
    end

    self.close = function()
        if closed then return end
        closed = true
        for _, font in pairs(font_cache) do
            ttf.TTF_CloseFont(font)
        end
        sdl3.release_ttf()
    end

    return self
end

M.T = T

return M
