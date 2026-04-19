local pvm = require("pvm")
local demo_asdl = require("demo_asdl")

local T = demo_asdl.T
local Core = T.Core
local Content = T.Content
local MNotes = T.MultiNotes

local M = {}
local content_store_cache = setmetatable({}, { __mode = "k" })

local function note_index(project, id)
    for i = 1, #project.notes do
        if project.notes[i].id == id then return i end
    end
    return 0
end

local function doc_index(docs, id)
    local items = docs.items
    for i = 1, #items do
        if items[i].id == id then return i end
    end
    return 0
end

local function selected_index(project)
    return note_index(project, project.selected_note_id)
end

local function selected_note_ref_in_project(project)
    local i = selected_index(project)
    if i == 0 then return nil end
    return project.notes[i], i
end

local function note_doc(docs, id)
    local i = doc_index(docs, id)
    if i == 0 then return nil end
    return docs.items[i], i
end

local function copy_array(items)
    local out = {}
    for i = 1, #items do out[i] = items[i] end
    return out
end

local function make_seed_note(next_id)
    local id = "note-" .. tostring(next_id)
    return MNotes.Note(id, next_id), MNotes.NoteDoc(id, "Untitled note", "")
end

local function ensure_nonempty(project, docs)
    if #project.notes > 0 then return project, docs end
    local note, doc = make_seed_note(project.next_id)
    return MNotes.Project({ note }, note.id, project.next_id + 1), MNotes.Docs({ doc })
end

local function clamp_slot(index, count)
    if index < 1 then return 1 end
    if index > (count + 1) then return count + 1 end
    return index
end

local function move_note(project, id, index)
    local from_idx = note_index(project, id)
    if from_idx == 0 or #project.notes <= 1 then return project end

    local slot = clamp_slot(index, #project.notes)
    if slot == from_idx or slot == (from_idx + 1) then return project end

    local moving = project.notes[from_idx]
    local notes = {}
    for i = 1, #project.notes do
        if i ~= from_idx then
            notes[#notes + 1] = project.notes[i]
        end
    end

    if from_idx < slot then
        slot = slot - 1
    end
    if slot < 1 then slot = 1 end
    if slot > (#notes + 1) then slot = #notes + 1 end

    table.insert(notes, slot, moving)
    return pvm.with(project, { notes = notes })
end

local function note_content_id(note_id, slot)
    return Core.IdValue("note:" .. note_id .. ":" .. slot)
end

local function note_subtitle(body)
    if body == "" then return "Empty note" end
    if #body > 72 then
        return string.sub(body, 1, 72) .. "…"
    end
    return body
end

local function clear_drag_state(state)
    if state.drag == MNotes.NoDrag and state.drop == MNotes.NoDrop then
        return state
    end
    return pvm.with(state, {
        drag = MNotes.NoDrag,
        drop = MNotes.NoDrop,
    })
end

function M.initial_project()
    local notes = {
        MNotes.Note("note-1", 1),
        MNotes.Note("note-2", 2),
        MNotes.Note("note-3", 3),
        MNotes.Note("note-4", 4),
        MNotes.Note("note-5", 5),
        MNotes.Note("note-6", 6),
        MNotes.Note("note-7", 7),
        MNotes.Note("note-8", 8),
        MNotes.Note("note-9", 9),
        MNotes.Note("note-10", 10),
        MNotes.Note("note-11", 11),
        MNotes.Note("note-12", 12),
    }
    return MNotes.Project(notes, notes[1].id, 13)
end

function M.initial_docs()
    return MNotes.Docs {
        MNotes.NoteDoc("note-1", "Project Notes", "Notes for the next gps.lua UI push.\n\n- stabilize SDL3 text editing\n- validate multi-window routing\n- move from experiments to real examples\n- keep authored UI at the center"),
        MNotes.NoteDoc("note-2", "Release Draft", "Release draft\n\nThe new multi-window app demonstrates:\n\n• generic ui.session orchestration\n• authored workspace chrome\n• SDL3 backend isolation\n• shared project state with separate windows"),
        MNotes.NoteDoc("note-3", "Ideas", "- split browser/editor/inspector\n- add save/load later\n- maybe tags and search\n- maybe preview window"),
        MNotes.NoteDoc("note-4", "Input Edge Cases", "- confirm IME rect updates\n- watch focus lost during drag\n- make wheel targeting match visible clip\n- test long lists with nested scroll"),
        MNotes.NoteDoc("note-5", "Recipe Backlog", "- activatable rows\n- reorderable collections\n- edit surfaces\n- scroll view with a real scrollbar helper"),
        MNotes.NoteDoc("note-6", "Text QA", "- wrapped caret affinity\n- trailing spaces\n- empty text safety\n- cluster hit-testing\n- composition overlay placement"),
        MNotes.NoteDoc("note-7", "Session Notes", "Dirty redraw mode feels better once timed redraw is explicit.\n\nNext: ensure scroll scheduling and caret blink stay independent."),
        MNotes.NoteDoc("note-8", "Browser Polish", "Need enough authored rows to force overflow so the scrollbar and wheel path are visible in the real app."),
        MNotes.NoteDoc("note-9", "Drag QA", "- drag start threshold\n- drop preview clipping\n- pointer cancel on focus loss\n- drop slot visibility inside scroll regions"),
        MNotes.NoteDoc("note-10", "Future", "- draggable scrollbar thumbs\n- page up/down support\n- home/end to top/bottom\n- authored list keyboard navigation"),
        MNotes.NoteDoc("note-11", "Theme Audit", "- contrast on dark surfaces\n- hover states on scroll thumb\n- editor chrome vs browser chrome\n- subtle but visible borders"),
        MNotes.NoteDoc("note-12", "Large Note", "This extra note exists mostly to ensure the browser rail overflows immediately in the demo so scroll behavior is obvious without creating test content first."),
    }
end

function M.initial_state()
    return MNotes.State(M.initial_project(), M.initial_docs(), MNotes.NoDrag, MNotes.NoDrop)
end

function M.note_doc(state, id)
    if id == nil or id == "" then return nil end
    local doc = note_doc(state.docs, id)
    return doc
end

function M.content_store(state)
    local docs = state.docs
    local cached = content_store_cache[docs]
    if cached ~= nil then return cached end

    local items = {}
    for i = 1, #docs.items do
        local doc = docs.items[i]
        items[#items + 1] = Content.Text(note_content_id(doc.id, "title"), doc.title)
        items[#items + 1] = Content.Text(note_content_id(doc.id, "body"), doc.body ~= "" and doc.body or "Empty note")
        items[#items + 1] = Content.Text(note_content_id(doc.id, "subtitle"), note_subtitle(doc.body))
    end

    cached = Content.Store(items)
    content_store_cache[docs] = cached
    return cached
end

function M.selected_note(state_or_project)
    if pvm.classof(state_or_project) == MNotes.State then
        local ref = selected_note_ref_in_project(state_or_project.project)
        if ref == nil then return nil end
        return M.note_doc(state_or_project, ref.id)
    end
    local ref = selected_note_ref_in_project(state_or_project)
    return ref
end

function M.apply(state, event)
    local cls = pvm.classof(event)

    if pvm.classof(state) ~= MNotes.State then
        state = MNotes.State(state, MNotes.Docs({}), MNotes.NoDrag, MNotes.NoDrop)
    end

    if cls == MNotes.BeginDragNote then
        if note_index(state.project, event.id) == 0 then return state end
        return pvm.with(state, {
            drag = MNotes.DragNote(event.id),
            drop = MNotes.NoDrop,
        })
    end

    if cls == MNotes.PreviewInsertAt then
        if state.drag == MNotes.NoDrag then return state end
        local next_drop = MNotes.InsertAt(clamp_slot(event.index, #state.project.notes))
        if state.drop == next_drop then return state end
        return pvm.with(state, { drop = next_drop })
    end

    if event == MNotes.ClearDropPreview then
        if state.drop == MNotes.NoDrop then return state end
        return pvm.with(state, { drop = MNotes.NoDrop })
    end

    if cls == MNotes.CommitDragAt then
        local drag = state.drag
        if pvm.classof(drag) ~= MNotes.DragNote then
            return clear_drag_state(state)
        end
        local project = move_note(state.project, drag.id, event.index)
        if project == state.project and state.drag == MNotes.NoDrag and state.drop == MNotes.NoDrop then
            return state
        end
        return MNotes.State(project, state.docs, MNotes.NoDrag, MNotes.NoDrop)
    end

    if event == MNotes.CancelDrag then
        return clear_drag_state(state)
    end

    local project = state.project
    local docs = state.docs

    if cls == MNotes.SelectNote then
        if note_index(project, event.id) == 0 or project.selected_note_id == event.id then
            return state
        end
        project = pvm.with(project, { selected_note_id = event.id })

    elseif event == MNotes.NewNote then
        local note, doc = make_seed_note(project.next_id)
        local notes = copy_array(project.notes)
        local items = copy_array(docs.items)
        notes[#notes + 1] = note
        items[#items + 1] = doc
        project = MNotes.Project(notes, note.id, project.next_id + 1)
        docs = MNotes.Docs(items)

    elseif event == MNotes.DeleteSelected then
        local idx = selected_index(project)
        if idx == 0 then
            project, docs = ensure_nonempty(project, docs)
        else
            local id = project.notes[idx].id
            local notes = {}
            for i = 1, #project.notes do
                if i ~= idx then notes[#notes + 1] = project.notes[i] end
            end
            local items = {}
            for i = 1, #docs.items do
                if docs.items[i].id ~= id then items[#items + 1] = docs.items[i] end
            end
            if #notes == 0 then
                project, docs = ensure_nonempty(MNotes.Project({}, "", project.next_id), MNotes.Docs({}))
            else
                local next_idx = idx
                if next_idx > #notes then next_idx = #notes end
                project = MNotes.Project(notes, notes[next_idx].id, project.next_id)
                docs = MNotes.Docs(items)
            end
        end

    elseif cls == MNotes.MoveNote then
        local next_project = move_note(project, event.id, event.index)
        if next_project == project then return state end
        project = next_project

    elseif cls == MNotes.UpdateSelectedTitle then
        local ref = selected_note_ref_in_project(project)
        if ref == nil then return state end
        local doc, idx = note_doc(docs, ref.id)
        if doc == nil or doc.title == event.title then return state end
        local items = copy_array(docs.items)
        items[idx] = MNotes.NoteDoc(doc.id, event.title, doc.body)
        docs = MNotes.Docs(items)

    elseif cls == MNotes.UpdateSelectedBody then
        local ref = selected_note_ref_in_project(project)
        if ref == nil then return state end
        local doc, idx = note_doc(docs, ref.id)
        if doc == nil or doc.body == event.body then return state end
        local items = copy_array(docs.items)
        items[idx] = MNotes.NoteDoc(doc.id, doc.title, event.body)
        docs = MNotes.Docs(items)

    else
        return state
    end

    if project == state.project and docs == state.docs then
        return state
    end

    local next_state = pvm.with(state, {
        project = project,
        docs = docs,
    })
    local drag = next_state.drag
    if pvm.classof(drag) == MNotes.DragNote and note_index(project, drag.id) == 0 then
        next_state = clear_drag_state(next_state)
    end
    if cls == MNotes.MoveNote then
        next_state = clear_drag_state(next_state)
    end
    return next_state
end

return M
