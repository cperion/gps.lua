local ui_asdl = require("ui.asdl")

local T = ui_asdl.T

T:Define [[
    module MultiNotes {
        Note = (string id,
                number created_order) unique

        NoteDoc = (string id,
                   string title,
                   string body)

        Docs = (MultiNotes.NoteDoc* items)

        Project = (MultiNotes.Note* notes,
                   string selected_note_id,
                   number next_id) unique

        Drag = NoDrag
             | DragNote(string id) unique

        Drop = NoDrop
             | InsertAt(number index) unique

        State = (MultiNotes.Project project,
                 MultiNotes.Docs docs,
                 MultiNotes.Drag drag,
                 MultiNotes.Drop drop)

        Event = SelectNote(string id)
              | NewNote
              | DeleteSelected
              | MoveNote(string id, number index) unique
              | BeginDragNote(string id) unique
              | PreviewInsertAt(number index) unique
              | ClearDropPreview
              | CommitDragAt(number index) unique
              | CancelDrag
              | UpdateSelectedTitle(string title)
              | UpdateSelectedBody(string body)
    }
]]

return {
    T = T,
}
