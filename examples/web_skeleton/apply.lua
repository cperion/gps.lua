local pvm = require("pvm")

local M = {}

local function copy_table(t)
    local out = {}
    for k, v in pairs(t or {}) do
        out[k] = v
    end
    return out
end

function M.bind(T)
    local Low = T.App.Low
    local Medium = T.App.Medium
    local High = T.App.High

    local All = T.App.All
    local Open = T.App.Open
    local Done = T.App.Done

    local function next_priority(priority)
        if priority == Low then
            return Medium
        end
        if priority == Medium then
            return High
        end
        return Low
    end

    local function normalize_text(value)
        value = tostring(value or "")
        value = value:gsub("^%s+", "")
        value = value:gsub("%s+$", "")
        return value
    end

    local function map_task(tasks, id, fn)
        local out = {}
        local changed = false

        for i = 1, #tasks do
            local task = tasks[i]
            if task.id == id then
                local new_task = fn(task)
                out[i] = new_task
                if new_task ~= task then
                    changed = true
                end
            else
                out[i] = task
            end
        end

        if not changed then
            return tasks, false
        end
        return out, true
    end

    local function filter_tasks(tasks, keep)
        local out = {}
        local n = 0
        local changed = false

        for i = 1, #tasks do
            local task = tasks[i]
            if keep(task) then
                n = n + 1
                out[n] = task
            else
                changed = true
            end
        end

        if not changed then
            return tasks, false
        end
        return out, true
    end

    local function apply_state(state, event)
        if event.kind == "AddTask" then
            local title = normalize_text(event.title)
            local notes = normalize_text(event.notes)
            local id = tostring(state.next_id)

            if title == "" then
                if notes ~= "" then
                    title = notes
                else
                    title = "Task " .. id
                end
            end

            local new_task = T.App.Task(id, title, notes, event.priority, false)
            local tasks = {}
            for i = 1, #state.tasks do
                tasks[i] = state.tasks[i]
            end
            tasks[#tasks + 1] = new_task

            return pvm.with(state, {
                tasks = tasks,
                next_id = state.next_id + 1,
            })
        end

        if event == T.Event.ClearCompleted then
            local tasks, changed = filter_tasks(state.tasks, function(task)
                return not task.done
            end)
            if not changed then
                return state
            end
            return pvm.with(state, { tasks = tasks })
        end

        if event.kind == "ToggleTask" then
            local tasks, changed = map_task(state.tasks, event.id, function(task)
                return pvm.with(task, { done = not task.done })
            end)
            if not changed then
                return state
            end
            return pvm.with(state, { tasks = tasks })
        end

        if event.kind == "DeleteTask" then
            local tasks, changed = filter_tasks(state.tasks, function(task)
                return task.id ~= event.id
            end)
            if not changed then
                return state
            end
            return pvm.with(state, { tasks = tasks })
        end

        if event.kind == "CycleTaskPriority" then
            local tasks, changed = map_task(state.tasks, event.id, function(task)
                return pvm.with(task, { priority = next_priority(task.priority) })
            end)
            if not changed then
                return state
            end
            return pvm.with(state, { tasks = tasks })
        end

        if event.kind == "SetTaskTitle" then
            local tasks, changed = map_task(state.tasks, event.id, function(task)
                local value = normalize_text(event.value)
                if value == "" then
                    return task
                end
                return pvm.with(task, { title = value })
            end)
            if not changed then
                return state
            end
            return pvm.with(state, { tasks = tasks })
        end

        if event.kind == "SetTaskNotes" then
            local tasks, changed = map_task(state.tasks, event.id, function(task)
                return pvm.with(task, { notes = event.value })
            end)
            if not changed then
                return state
            end
            return pvm.with(state, { tasks = tasks })
        end

        return state
    end

    local function apply_request(req, event)
        local next_req = copy_table(req)

        if event.kind == "SetDraftTitle" then
            next_req.draft_title = event.value
            return next_req, true
        end

        if event.kind == "SetDraftNotes" then
            next_req.draft_notes = event.value
            return next_req, true
        end

        if event.kind == "SetSearch" then
            next_req.search = event.value
            return next_req, true
        end

        if event.kind == "SetFilter" then
            next_req.filter = event.value
            return next_req, true
        end

        if event == T.Event.CycleDraftPriority then
            next_req.draft_priority = next_priority(req.draft_priority or Medium)
            return next_req, true
        end

        return req, false
    end

    local function clear_composer(req)
        local next_req = copy_table(req)
        next_req.draft_title = ""
        next_req.draft_notes = ""
        return next_req
    end

    local function is_request_event(event)
        return event.kind == "SetDraftTitle"
            or event.kind == "SetDraftNotes"
            or event.kind == "SetSearch"
            or event.kind == "SetFilter"
            or event == T.Event.CycleDraftPriority
    end

    return {
        state = apply_state,
        request = apply_request,
        clear_composer = clear_composer,
        is_request_event = is_request_event,
        defaults = function(req)
            local next_req = copy_table(req)
            next_req.logged_in = next_req.logged_in ~= false
            next_req.username = next_req.username or "cedric"
            next_req.search = tostring(next_req.search or "")
            next_req.draft_title = tostring(next_req.draft_title or "")
            next_req.draft_notes = tostring(next_req.draft_notes or "")
            next_req.filter = next_req.filter or All
            next_req.draft_priority = next_req.draft_priority or Medium
            return next_req
        end,
        priority_name = function(priority)
            if priority == Low then
                return "Low"
            end
            if priority == Medium then
                return "Medium"
            end
            return "High"
        end,
        filter_name = function(filter)
            if filter == Open then
                return "Open"
            end
            if filter == Done then
                return "Done"
            end
            return "All"
        end,
    }
end

return M
