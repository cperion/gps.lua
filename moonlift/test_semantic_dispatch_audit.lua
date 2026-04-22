package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local files = {
    "moonlift/lua/moonlift/lower_elab_to_sem.lua",
    "moonlift/lua/moonlift/resolve_sem_layout.lua",
    "moonlift/lua/moonlift/resolve_sem_residence.lua",
    "moonlift/lua/moonlift/lower_sem_to_back.lua",
    "moonlift/lua/moonlift/lower_sem_to_back_const_eval.lua",
    "moonlift/lua/moonlift/lower_sem_to_back_materialize.lua",
    "moonlift/lua/moonlift/lower_sem_to_back_const_data.lua",
    "moonlift/lua/moonlift/lower_sem_to_back_ops.lua",
}

local rules = {
    { id = "raw-kind-dispatch", pattern = "%.kind%s*[!~=]=" },
    { id = "raw-sem-type-eq", pattern = "==%s*Sem%.SemT" },
    { id = "raw-sem-type-ne", pattern = "~=%s*Sem%.SemT" },
    { id = "raw-type-is-intlike", pattern = "type_is_intlike%s*%(" },
    { id = "raw-type-is-float", pattern = "type_is_float%s*%(" },
    { id = "raw-type-is-signed-int", pattern = "type_is_signed_int%s*%(" },
    { id = "raw-binding-is-scalarish", pattern = "binding_is_scalarish%s*%(" },
}

local function read_text(path)
    local f = assert(io.open(path, "rb"))
    local text = assert(f:read("*a"))
    f:close()
    return text
end

local function scan_file(path)
    local text = read_text(path)
    local findings = {}
    local line_no = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line_no = line_no + 1
        for _, rule in ipairs(rules) do
            if line:find(rule.pattern) then
                findings[#findings + 1] = string.format("%s:%d:%s:%s", path, line_no, rule.id, line)
            end
        end
    end
    return findings
end

local function load_baseline(path)
    local allowed = {}
    local text = read_text(path)
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then
            allowed[line] = true
        end
    end
    return allowed
end

local baseline = load_baseline("moonlift/semantic_dispatch_audit_baseline.txt")
local unexpected = {}
local findings = {}
for _, path in ipairs(files) do
    local file_findings = scan_file(path)
    for i = 1, #file_findings do
        local finding = file_findings[i]
        findings[#findings + 1] = finding
        if not baseline[finding] then
            unexpected[#unexpected + 1] = finding
        end
    end
end

if #unexpected > 0 then
    io.stderr:write("moonlift semantic dispatch audit failed; unexpected non-phase semantic dispatch sites:\n")
    for i = 1, #unexpected do
        io.stderr:write(unexpected[i] .. "\n")
    end
    io.stderr:write("\nIf a new site is truly unavoidable, audit it explicitly and update moonlift/semantic_dispatch_audit_baseline.txt in the same change.\n")
    os.exit(1)
end

print(string.format("moonlift semantic dispatch audit ok (%d baseline findings, no regressions)", #findings))
