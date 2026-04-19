local bit = require("bit")
local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Layout = T.Layout

local M = {}

local HUGE = math.huge
local systems = {}

local SDL_TTF_SUBSTRING_DIRECTION_MASK = 0x000000FF
local SDL_TTF_SUBSTRING_TEXT_START = 0x00000100
local SDL_TTF_SUBSTRING_LINE_START = 0x00000200
local SDL_TTF_SUBSTRING_LINE_END = 0x00000400
local SDL_TTF_SUBSTRING_TEXT_END = 0x00000800

local function finite(n)
    return n ~= nil and n < HUGE
end

local function max0(n)
    if n < 0 then return 0 end
    return n
end

local function round(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function approx_advance(style)
    local advance = style.font_size * 0.6 + (style.tracking or 0)
    if advance < 1 then advance = 1 end
    return advance
end

local function approx_baseline(style)
    return round(style.font_size * 0.8)
end

local function default_line_h(style)
    return style.leading > 0 and style.leading or style.font_size
end

local function line_width_approx(style, text)
    if text == nil or #text == 0 then return 0 end
    return round(#text * approx_advance(style))
end

local function split_paragraphs(text)
    local out = {}
    local start_i = 1
    while true do
        local i = string.find(text, "\n", start_i, true)
        if i == nil then
            out[#out + 1] = string.sub(text, start_i)
            break
        end
        out[#out + 1] = string.sub(text, start_i, i - 1)
        start_i = i + 1
    end
    if #out == 0 then out[1] = "" end
    return out
end

local function wrap_para_approx(style, para, max_w)
    if not finite(max_w) then
        return { para }, line_width_approx(style, para)
    end

    local limit = max0(max_w)
    if limit <= 0 then
        return { "" }, 0
    end

    if para == "" then
        return { "" }, 0
    end

    local lines = {}
    local line = ""
    local line_w = 0
    local max_line_w = 0

    local i = 1
    while i <= #para do
        local ws_s, ws_e = string.find(para, "^%s+", i)
        if ws_s then
            i = ws_e + 1
        else
            local w_s, w_e = string.find(para, "^%S+", i)
            if not w_s then break end
            local word = string.sub(para, w_s, w_e)
            i = w_e + 1

            local candidate = line == "" and word or (line .. " " .. word)
            local candidate_w = line_width_approx(style, candidate)
            if line == "" or candidate_w <= limit then
                line = candidate
                line_w = candidate_w
            else
                lines[#lines + 1] = line
                if line_w > max_line_w then max_line_w = line_w end

                if line_width_approx(style, word) <= limit then
                    line = word
                    line_w = line_width_approx(style, word)
                else
                    local chars_per_line = math.max(1, math.floor(limit / approx_advance(style)))
                    local pos = 1
                    while pos <= #word do
                        local piece = string.sub(word, pos, pos + chars_per_line - 1)
                        local piece_w = line_width_approx(style, piece)
                        lines[#lines + 1] = piece
                        if piece_w > max_line_w then max_line_w = piece_w end
                        pos = pos + chars_per_line
                    end
                    line = ""
                    line_w = 0
                end
            end
        end
    end

    if line ~= "" or #lines == 0 then
        lines[#lines + 1] = line
        if line_w > max_line_w then max_line_w = line_w end
    end

    return lines, max_line_w
end

local function normalize_flow(flow)
    if flow == nil or flow == Layout.FlowUnknown then return Layout.FlowUnknown end
    if flow == Layout.FlowLTR or flow == 4 or flow == "ltr" or flow == "LTR" then return Layout.FlowLTR end
    if flow == Layout.FlowRTL or flow == 5 or flow == "rtl" or flow == "RTL" then return Layout.FlowRTL end
    if flow == Layout.FlowTTB or flow == 6 or flow == "ttb" or flow == "TTB" then return Layout.FlowTTB end
    if flow == Layout.FlowBTT or flow == 7 or flow == "btt" or flow == "BTT" then return Layout.FlowBTT end
    return Layout.FlowUnknown
end

local function normalize_glyph(glyph)
    if glyph == nil then
        return nil
    end
    if pvm.classof(glyph) == Layout.Glyph then
        return glyph
    end
    if type(glyph) ~= "table" then
        error("ui.text: glyph must be Layout.Glyph or a table", 4)
    end
    return Layout.Glyph(
        glyph.glyph_id or glyph.id or 0,
        glyph.cluster or 0,
        glyph.x or 0,
        glyph.y or 0,
        glyph.advance_x or glyph.advance or 0,
        glyph.advance_y or 0,
        glyph.offset_x or 0,
        glyph.offset_y or 0
    )
end

local function normalize_glyphs(glyphs)
    if glyphs == nil then return {} end
    local out = {}
    for i = 1, #glyphs do
        out[i] = normalize_glyph(glyphs[i])
    end
    return out
end

local function raw_run_text(run, fallback_text)
    if type(run) == "string" then return run end
    if type(run) == "table" then return run.text or fallback_text or "" end
    return fallback_text or ""
end

local function raw_run_byte_range(run, default_start, default_end)
    if type(run) == "table" then
        local start_i = run.byte_start or run.offset or default_start
        local finish_i = run.byte_end
        if finish_i == nil and run.offset ~= nil and run.length ~= nil then
            finish_i = run.offset + run.length
        end
        if finish_i == nil then
            finish_i = default_end
        end
        return start_i, finish_i
    end
    return default_start, default_end
end

local function normalize_run(style, run, fallback_text, line_h, baseline, default_byte_start, default_byte_end)
    if pvm.classof(run) == Layout.TextRun then
        return run
    end

    local run_text = raw_run_text(run, fallback_text)
    local start_i, finish_i = raw_run_byte_range(run, default_byte_start, default_byte_end)

    if type(run) == "string" then
        local w = line_width_approx(style, run)
        return Layout.TextRun(0, 0, w, line_h, baseline, start_i, finish_i, style.font_id, style.font_size, style.font_weight, style.fg, run, {})
    end

    if type(run) ~= "table" then
        error("ui.text: run must be Layout.TextRun, string, or table", 4)
    end

    local run_line_h = run.h or run.height or line_h
    local run_baseline = run.baseline or baseline
    return Layout.TextRun(
        run.x or 0,
        run.y or 0,
        run.w or run.width or line_width_approx(style, run_text),
        run_line_h,
        run_baseline,
        start_i,
        finish_i,
        run.font_id or style.font_id,
        run.font_size or style.font_size,
        run.font_weight or style.font_weight,
        run.fg or style.fg,
        run_text,
        normalize_glyphs(run.glyphs)
    )
end

local function run_text_len(run)
    if pvm.classof(run) == Layout.TextRun then
        return #run.text
    end
    return #raw_run_text(run, "")
end

local function run_extent(runs)
    local extent = 0
    for i = 1, #runs do
        local run = runs[i]
        local x2 = run.x + run.w
        if x2 > extent then extent = x2 end
    end
    return extent
end

local function raw_line_text_len(line)
    if type(line) == "string" then
        return #line
    end
    if type(line) ~= "table" then
        return 0
    end
    if line.text ~= nil then
        return #line.text
    end
    if line.runs ~= nil then
        local total = 0
        for i = 1, #line.runs do
            total = total + run_text_len(line.runs[i])
        end
        return total
    end
    return 0
end

local function normalize_line(style, line, index, line_h, baseline, default_byte_start, default_byte_end)
    local default_y = (index - 1) * line_h

    if pvm.classof(line) == Layout.TextLine then
        return line
    end

    if type(line) == "string" then
        local run = normalize_run(style, line, line, line_h, baseline, default_byte_start, default_byte_end)
        return Layout.TextLine(0, default_y, run.w, line_h, baseline, default_byte_start, default_byte_end, { run })
    end

    if type(line) ~= "table" then
        error("ui.text: line must be Layout.TextLine, string, or table", 4)
    end

    local runs_src = line.runs
    local runs = {}
    local cursor = default_byte_start
    if runs_src ~= nil then
        for i = 1, #runs_src do
            local raw_run = runs_src[i]
            local estimated_len = run_text_len(raw_run)
            local run_start = type(raw_run) == "table" and (raw_run.byte_start or raw_run.offset) or nil
            if run_start == nil then run_start = cursor end
            local run_end = type(raw_run) == "table" and raw_run.byte_end or nil
            if run_end == nil and type(raw_run) == "table" and raw_run.offset ~= nil and raw_run.length ~= nil then
                run_end = raw_run.offset + raw_run.length
            end
            if run_end == nil then run_end = run_start + estimated_len end
            runs[i] = normalize_run(style, raw_run, nil, line_h, baseline, run_start, run_end)
            cursor = run_end
        end
    else
        runs[1] = normalize_run(style, line, line.text or "", line_h, baseline, default_byte_start, default_byte_end)
    end

    local line_h_v = line.h or line.height or line_h
    local line_baseline = line.baseline or baseline
    local line_w = line.w or line.width or run_extent(runs)
    return Layout.TextLine(
        line.x or 0,
        line.y or default_y,
        line_w,
        line_h_v,
        line_baseline,
        line.byte_start or line.offset or default_byte_start,
        line.byte_end or ((line.offset ~= nil and line.length ~= nil) and (line.offset + line.length)) or default_byte_end,
        runs
    )
end

local function normalize_flags(src)
    local flags = type(src) == "table" and src.flags or nil
    local flow = type(src) == "table" and (src.flow or src.direction) or nil
    local text_start = type(src) == "table" and (src.text_start or src.at_text_start) or false
    local line_start = type(src) == "table" and (src.line_start or src.at_line_start) or false
    local line_end = type(src) == "table" and (src.line_end or src.at_line_end) or false
    local text_end = type(src) == "table" and (src.text_end or src.at_text_end) or false

    if type(flags) == "number" then
        flow = bit.band(flags, SDL_TTF_SUBSTRING_DIRECTION_MASK)
        if bit.band(flags, SDL_TTF_SUBSTRING_TEXT_START) ~= 0 then text_start = true end
        if bit.band(flags, SDL_TTF_SUBSTRING_LINE_START) ~= 0 then line_start = true end
        if bit.band(flags, SDL_TTF_SUBSTRING_LINE_END) ~= 0 then line_end = true end
        if bit.band(flags, SDL_TTF_SUBSTRING_TEXT_END) ~= 0 then text_end = true end
    end

    return normalize_flow(flow), text_start, line_start, line_end, text_end
end

local function cluster_byte_range(src, line)
    local byte_start = src.byte_start or src.offset
    if byte_start == nil then byte_start = line.byte_start end
    local byte_end = src.byte_end
    if byte_end == nil and src.offset ~= nil and src.length ~= nil then
        byte_end = src.offset + src.length
    end
    if byte_end == nil then byte_end = line.byte_end end
    return byte_start, byte_end
end

local function normalize_cluster(src, line, cluster_index, line_index)
    if pvm.classof(src) == Layout.TextCluster then
        return src
    end

    if type(src) ~= "table" then
        error("ui.text: cluster must be Layout.TextCluster or a table", 4)
    end

    local flow = normalize_flags(src)
    local byte_start, byte_end = cluster_byte_range(src, line)

    return Layout.TextCluster(
        flow,
        src.cluster_index or cluster_index,
        src.line_index or src.line or line_index,
        byte_start,
        byte_end,
        src.x or 0,
        src.y or 0,
        src.w or src.width or 0,
        src.h or src.height or line.h
    )
end

local function normalize_boundary(src, line, boundary_index, line_index)
    if pvm.classof(src) == Layout.TextBoundary then
        return src
    end

    if type(src) ~= "table" then
        error("ui.text: boundary must be Layout.TextBoundary or a table", 4)
    end

    local flow, text_start, line_start, line_end, text_end = normalize_flags(src)
    local byte_offset = src.byte_offset or src.byte_start or src.offset
    if byte_offset == nil then byte_offset = line.byte_end end

    return Layout.TextBoundary(
        flow,
        src.boundary_index or boundary_index,
        src.line_index or src.line or line_index,
        byte_offset,
        src.x or 0,
        src.y or 0,
        src.w or src.width or 0,
        src.h or src.height or line.h,
        text_start,
        line_start,
        line_end,
        text_end
    )
end

local function synthesize_clusters(lines)
    local out = {}
    local cluster_index = 1

    for line_index = 1, #lines do
        local line = lines[line_index]
        local runs = line.runs

        if #runs == 0 then
            out[#out + 1] = Layout.TextCluster(
                Layout.FlowUnknown,
                cluster_index,
                line_index,
                line.byte_start,
                line.byte_end,
                line.x,
                line.y,
                0,
                line.h
            )
            cluster_index = cluster_index + 1
        else
            for i = 1, #runs do
                local run = runs[i]
                out[#out + 1] = Layout.TextCluster(
                    Layout.FlowUnknown,
                    cluster_index,
                    line_index,
                    run.byte_start,
                    run.byte_end,
                    line.x + run.x,
                    line.y + run.y,
                    run.w,
                    run.h
                )
                cluster_index = cluster_index + 1
            end
        end
    end

    return out
end

local function synthesize_boundaries(lines, clusters)
    local out = {}
    local boundary_index = 1

    for line_index = 1, #lines do
        local line = lines[line_index]
        local first_cluster = nil
        local last_cluster = nil
        for i = 1, #clusters do
            local cluster = clusters[i]
            if cluster.line_index == line_index then
                if first_cluster == nil then first_cluster = cluster end
                last_cluster = cluster
            end
        end

        local start_x = first_cluster and first_cluster.x or line.x
        local end_x = last_cluster and (last_cluster.x + last_cluster.w) or line.x
        local start_byte = first_cluster and first_cluster.byte_start or line.byte_start
        local end_byte = last_cluster and last_cluster.byte_end or line.byte_end

        out[#out + 1] = Layout.TextBoundary(
            Layout.FlowUnknown,
            boundary_index,
            line_index,
            start_byte,
            start_x,
            line.y,
            0,
            line.h,
            line_index == 1,
            true,
            false,
            false
        )
        boundary_index = boundary_index + 1

        out[#out + 1] = Layout.TextBoundary(
            Layout.FlowUnknown,
            boundary_index,
            line_index,
            end_byte,
            end_x,
            line.y,
            0,
            line.h,
            false,
            false,
            true,
            line_index == #lines
        )
        boundary_index = boundary_index + 1
    end

    return out
end

local function split_cluster_like_records(lines, raw_clusters)
    if raw_clusters == nil then
        return nil, nil
    end

    local visual = {}
    local boundaries = {}
    for i = 1, #raw_clusters do
        local raw = raw_clusters[i]
        local line_index = 1
        if type(raw) == "table" and (raw.line_index or raw.line) ~= nil then
            line_index = raw.line_index or raw.line
        end
        if line_index < 1 then line_index = 1 end
        if line_index > #lines then line_index = #lines end
        local line = lines[line_index] or lines[1]

        if pvm.classof(raw) == Layout.TextBoundary then
            boundaries[#boundaries + 1] = raw
        else
            local byte_start, byte_end = cluster_byte_range(raw, line)
            local is_boundary = byte_start == byte_end
            if is_boundary then
                boundaries[#boundaries + 1] = raw
            else
                visual[#visual + 1] = raw
            end
        end
    end

    return visual, boundaries
end

local function normalize_clusters(lines, raw_clusters)
    local src = raw_clusters
    if src == nil then
        return synthesize_clusters(lines)
    end

    local out = {}
    for i = 1, #src do
        local raw = src[i]
        local line_index = 1
        if type(raw) == "table" and (raw.line_index or raw.line) ~= nil then
            line_index = raw.line_index or raw.line
        end
        if line_index < 1 then line_index = 1 end
        if line_index > #lines then line_index = #lines end
        local line = lines[line_index] or lines[1]
        out[i] = normalize_cluster(raw, line, i, line_index)
    end

    return out
end

local function merge_duplicate_boundaries(src)
    if #src <= 1 then return src end

    local out = {}
    local i = 1
    while i <= #src do
        local b = src[i]
        local j = i + 1
        while j <= #src do
            local n = src[j]
            if n.line_index ~= b.line_index
            or n.byte_offset ~= b.byte_offset then
                break
            end
            local x = b.x
            if b.flow == Layout.FlowRTL then
                if n.x < x then x = n.x end
            else
                if n.x > x then x = n.x end
            end
            b = Layout.TextBoundary(
                b.flow,
                b.boundary_index,
                b.line_index,
                b.byte_offset,
                x,
                b.y,
                b.w,
                b.h,
                b.text_start or n.text_start,
                b.line_start or n.line_start,
                b.line_end or n.line_end,
                b.text_end or n.text_end
            )
            j = j + 1
        end
        out[#out + 1] = b
        i = j
    end

    for k = 1, #out do
        local b = out[k]
        if b.boundary_index ~= k then
            out[k] = Layout.TextBoundary(
                b.flow,
                k,
                b.line_index,
                b.byte_offset,
                b.x,
                b.y,
                b.w,
                b.h,
                b.text_start,
                b.line_start,
                b.line_end,
                b.text_end
            )
        end
    end

    return out
end

local function normalize_boundaries(lines, clusters, raw_boundaries)
    local src = raw_boundaries
    if src == nil then
        return synthesize_boundaries(lines, clusters)
    end

    local out = {}
    for i = 1, #src do
        local raw = src[i]
        local line_index = 1
        if type(raw) == "table" and (raw.line_index or raw.line) ~= nil then
            line_index = raw.line_index or raw.line
        end
        if line_index < 1 then line_index = 1 end
        if line_index > #lines then line_index = #lines end
        local line = lines[line_index] or lines[1]
        out[i] = normalize_boundary(raw, line, i, line_index)
    end

    out = merge_duplicate_boundaries(out)

    for i = 1, #out do
        local boundary = out[i]
        local prev_boundary = out[i - 1]
        local next_boundary = out[i + 1]
        local want_text_start = boundary.text_start or i == 1
        local want_line_start = boundary.line_start or prev_boundary == nil or prev_boundary.line_index ~= boundary.line_index
        local want_line_end = boundary.line_end or next_boundary == nil or next_boundary.line_index ~= boundary.line_index
        local want_text_end = boundary.text_end or next_boundary == nil

        if boundary.text_start ~= want_text_start
        or boundary.line_start ~= want_line_start
        or boundary.line_end ~= want_line_end
        or boundary.text_end ~= want_text_end then
            out[i] = Layout.TextBoundary(
                boundary.flow,
                boundary.boundary_index,
                boundary.line_index,
                boundary.byte_offset,
                boundary.x,
                boundary.y,
                boundary.w,
                boundary.h,
                want_text_start,
                want_line_start,
                want_line_end,
                want_text_end
            )
        end
    end

    return out
end

local function normalize_lines(style, lines, measured_w, measured_h, baseline)
    local line_h = default_line_h(style)
    local out = {}
    local max_w = measured_w or 0
    local max_h = measured_h or 0
    local byte_cursor = 0

    for i = 1, #lines do
        local raw_line = lines[i]
        local estimated_len = raw_line_text_len(raw_line)
        local default_byte_start = type(raw_line) == "table" and (raw_line.byte_start or raw_line.offset) or nil
        if default_byte_start == nil then default_byte_start = byte_cursor end
        local default_byte_end = type(raw_line) == "table" and raw_line.byte_end or nil
        if default_byte_end == nil and type(raw_line) == "table" and raw_line.offset ~= nil and raw_line.length ~= nil then
            default_byte_end = raw_line.offset + raw_line.length
        end
        if default_byte_end == nil then default_byte_end = default_byte_start + estimated_len end

        local line = normalize_line(style, raw_line, i, line_h, baseline, default_byte_start, default_byte_end)
        out[i] = line
        byte_cursor = line.byte_end

        local x2 = line.x + line.w
        local y2 = line.y + line.h
        if x2 > max_w then max_w = x2 end
        if y2 > max_h then max_h = y2 end
    end

    if #out == 0 then
        out[1] = normalize_line(style, "", 1, line_h, baseline, 0, 0)
        max_h = math.max(max_h, line_h)
    end

    return out, max_w, max_h
end

local function build_layout(style, max_w, measured_w, measured_h, baseline, lines, clusters, boundaries)
    local normalized_lines, w, h = normalize_lines(style, lines or {}, measured_w, measured_h, baseline)
    local split_clusters, split_boundaries = split_cluster_like_records(normalized_lines, clusters)
    if split_clusters ~= nil then clusters = split_clusters end
    if boundaries == nil and split_boundaries ~= nil then boundaries = split_boundaries end
    local normalized_clusters = normalize_clusters(normalized_lines, clusters)
    local normalized_boundaries = normalize_boundaries(normalized_lines, normalized_clusters, boundaries)
    return Layout.TextLayout(style, max_w, w, h, baseline, normalized_lines, normalized_clusters, normalized_boundaries)
end

function M.approx_layout(style, constraint)
    local leading = default_line_h(style)
    local baseline = approx_baseline(style)
    local paragraphs = split_paragraphs(style.content or "")
    local line_texts = {}
    local measured_w = 0

    for i = 1, #paragraphs do
        local wrapped, para_w = wrap_para_approx(style, paragraphs[i], constraint.max_w)
        for j = 1, #wrapped do
            line_texts[#line_texts + 1] = wrapped[j]
        end
        if para_w > measured_w then measured_w = para_w end
    end

    if #line_texts == 0 then line_texts[1] = "" end

    return build_layout(
        style,
        constraint.max_w,
        measured_w,
        #line_texts * leading,
        baseline,
        line_texts,
        nil,
        nil
    )
end

local function from_result(style, constraint, result)
    if pvm.classof(result) == Layout.TextLayout then
        return result
    end

    if type(result) ~= "table" then
        error("ui.text: backend measure must return Layout.TextLayout or a table", 3)
    end

    local lines = result.lines or { style.content or "" }
    local baseline = result.baseline or approx_baseline(style)

    return build_layout(
        style,
        result.max_w or constraint.max_w,
        result.measured_w or result.width or 0,
        result.measured_h or result.height or 0,
        baseline,
        lines,
        result.clusters,
        result.boundaries
    )
end

function M.layout(style, constraint, system_key)
    if system_key == nil then
        return M.approx_layout(style, constraint)
    end

    local system = systems[system_key]
    if system == nil then
        return M.approx_layout(style, constraint)
    end

    local measure
    if type(system) == "function" then
        measure = system
    else
        measure = system.measure
    end
    if type(measure) ~= "function" then
        error("ui.text: registered system must be a function or { measure = fn }", 2)
    end

    return from_result(style, constraint, measure(style, constraint))
end

function M.register(key, system)
    local kt = type(key)
    if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then
        error("ui.text.register: key must be string, number, or boolean", 2)
    end
    if type(system) ~= "function" and type(system) ~= "table" then
        error("ui.text.register: system must be a function or table", 2)
    end
    systems[key] = system
    return key
end

function M.unregister(key)
    systems[key] = nil
end

function M.lookup(key)
    return systems[key]
end

M.T = T

return M
