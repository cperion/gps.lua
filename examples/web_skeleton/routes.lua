local M = {}

function M.bind(T, Resp)
    local All = T.App.All
    local Open = T.App.Open
    local Done = T.App.Done
    local High = T.App.High

    local function contains(haystack, needle)
        return haystack:find(needle, 1, true) ~= nil
    end

    local function lower(s)
        return tostring(s or ""):lower()
    end

    local function summary_of(tasks)
        local total = #tasks
        local open_n = 0
        local done_n = 0
        local high_n = 0

        for i = 1, #tasks do
            local task = tasks[i]
            if task.done then
                done_n = done_n + 1
            else
                open_n = open_n + 1
            end
            if task.priority == High then
                high_n = high_n + 1
            end
        end

        return T.Page.Summary(total, open_n, done_n, high_n)
    end

    local function find_task(tasks, id)
        for i = 1, #tasks do
            if tasks[i].id == id then
                return tasks[i]
            end
        end
        return nil
    end

    local function visible_tasks(tasks, search, filter)
        local needle = lower(search)
        local out = {}
        local n = 0

        for i = 1, #tasks do
            local task = tasks[i]
            local passes_filter = filter == All
                or (filter == Open and not task.done)
                or (filter == Done and task.done)

            local searchable = lower(task.title .. " " .. task.notes)
            local passes_search = needle == "" or contains(searchable, needle)

            if passes_filter and passes_search then
                n = n + 1
                out[n] = task
            end
        end

        return out
    end

    local API = {}

    function API.summary_of(tasks)
        return summary_of(tasks)
    end

    function API.find_task(tasks, id)
        return find_task(tasks, id)
    end

    function API.visible_tasks(tasks, search, filter)
        return visible_tasks(tasks, search, filter)
    end

    function API.home_view(nav, state, req)
        return T.Page.Home(
            nav,
            visible_tasks(state.tasks, req.search, req.filter),
            req.draft_title,
            req.draft_notes,
            req.search,
            req.filter,
            req.draft_priority,
            summary_of(state.tasks)
        )
    end

    function API.task_view(nav, state, id)
        local task = find_task(state.tasks, id)
        if not task then
            return nil
        end
        return T.Page.TaskDetail(nav, task, summary_of(state.tasks))
    end

    function API.make(nav_for, state_ref, H, stats_text)
        return {
            {
                method = "GET",
                path = "/",
                build = function(req)
                    local state = state_ref()
                    return Resp.ok_page(API.home_view(nav_for(req), state, req))
                end,
            },
            {
                method = "GET",
                path = "/task/:id",
                build = function(req, _state, params)
                    local state = state_ref()
                    local view = API.task_view(nav_for(req), state, params.id)
                    if view == nil then
                        return Resp.not_found_page(T.Page.NotFound(nav_for(req), req.path, summary_of(state.tasks)))
                    end
                    return Resp.ok_page(view)
                end,
            },
            {
                method = "GET",
                path = "/__stats",
                build = function(_req)
                    return Resp.html(200, { ["Content-Type"] = "text/plain; charset=utf-8" }, H.raw(stats_text()))
                end,
            },
        }
    end

    return API
end

return M
