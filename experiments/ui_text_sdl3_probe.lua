package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")

local FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
local T = ui.T
local sdl3 = ui.backends.sdl3

local function dump_layout(label, layout)
    print(("== %s =="):format(label))
    print(("size: %dx%d  lines=%d  clusters=%d  boundaries=%d  baseline=%d"):format(
        layout.measured_w,
        layout.measured_h,
        #layout.lines,
        #layout.clusters,
        #layout.boundaries,
        layout.baseline
    ))

    for i = 1, #layout.lines do
        local line = layout.lines[i]
        local run = line.runs[1]
        print(("  line[%d]: xywh=(%d,%d,%d,%d) bytes=[%d,%d) text=%q"):format(
            i,
            line.x, line.y, line.w, line.h,
            line.byte_start, line.byte_end,
            run and run.text or ""
        ))
    end

    for i = 1, #layout.clusters do
        local c = layout.clusters[i]
        print(("  cluster[%d]: line=%d flow=%s bytes=[%d,%d) rect=(%d,%d,%d,%d)"):format(
            i,
            c.line_index,
            tostring(c.flow),
            c.byte_start,
            c.byte_end,
            c.x, c.y, c.w, c.h
        ))
    end

    for i = 1, #layout.boundaries do
        local b = layout.boundaries[i]
        print(("  boundary[%d]: line=%d flow=%s byte=%d rect=(%d,%d,%d,%d) flags=%s%s%s%s"):format(
            i,
            b.line_index,
            tostring(b.flow),
            b.byte_offset,
            b.x, b.y, b.w, b.h,
            b.text_start and "T" or "-",
            b.line_start and "L" or "-",
            b.line_end and "E" or "-",
            b.text_end and "X" or "-"
        ))
    end
end

local function dump_range(sys, style, constraint, offset, length)
    local clusters = sys.range_query(style, constraint, offset, length)
    print(("range [%d,%s): %d cluster(s)"):format(offset, tostring(length), #clusters))
    for i = 1, #clusters do
        local c = clusters[i]
        print(("  range-cluster[%d]: line=%d bytes=[%d,%d) rect=(%d,%d,%d,%d)"):format(
            i, c.line_index, c.byte_start, c.byte_end, c.x, c.y, c.w, c.h
        ))
    end
end

local function dump_hit(sys, style, constraint, x, y)
    local c = sys.hit_test(style, constraint, x, y)
    print(("hit (%d,%d): line=%d bytes=[%d,%d) rect=(%d,%d,%d,%d)"):format(
        x, y,
        c.line_index,
        c.byte_start,
        c.byte_end,
        c.x, c.y, c.w, c.h
    ))
end

local function main()
    local sys = sdl3.new_text_system({ default_font = FONT })

    local samples = {
        {
            label = "wrap-english",
            style = T.Layout.TextStyle(1, 18, 400, 0xffffffff, 0, 22, 0, "abc def ghi jkl mno"),
            constraint = T.Layout.Constraint(80, math.huge),
            range_offset = 4,
            range_length = 7,
            hit_x = 10,
            hit_y = 5,
        },
        {
            label = "multiline",
            style = T.Layout.TextStyle(1, 18, 400, 0xffffffff, 0, 22, 0, "hello\nworld again"),
            constraint = T.Layout.Constraint(200, math.huge),
            range_offset = 0,
            range_length = -1,
            hit_x = 12,
            hit_y = 28,
        },
    }

    for i = 1, #samples do
        local sample = samples[i]
        local key = "probe-" .. sample.label
        ui.text.register(key, sys)
        local layout = ui.text.layout(sample.style, sample.constraint, key)
        dump_layout(sample.label, layout)
        dump_range(sys, sample.style, sample.constraint, sample.range_offset, sample.range_length)
        dump_hit(sys, sample.style, sample.constraint, sample.hit_x, sample.hit_y)
        print("")
    end

    sys.close()
end

main()
