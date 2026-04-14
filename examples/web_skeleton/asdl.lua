local M = {}

function M.Define(T)
    T:Define [[
        module App {
            Priority = Low | Medium | High
            Filter = All | Open | Done

            Task = (string id, string title, string notes, App.Priority priority, boolean done) unique
            State = (App.Task* tasks, number next_id) unique
        }

        module Page {
            Nav = (string current_path, boolean logged_in, string? username) unique
            Summary = (number total, number open, number done, number high) unique

            View = Home(
                        Page.Nav nav,
                        App.Task* tasks,
                        string draft_title,
                        string draft_notes,
                        string search,
                        App.Filter filter,
                        App.Priority draft_priority,
                        Page.Summary summary
                    ) unique
                 | TaskDetail(Page.Nav nav, App.Task task, Page.Summary summary) unique
                 | NotFound(Page.Nav nav, string path, Page.Summary summary) unique
        }

        module AppWeb {
            Header = (string name, string value) unique

            Body = PageBody(Page.View view) unique
                 | HtmlBody(Html.Node node) unique

            Response = (number status, AppWeb.Header* headers, AppWeb.Body body) unique
        }

        module Event {
            Msg = AddTask(string title, string notes, App.Priority priority) unique
                 | ClearCompleted unique
                 | SetDraftTitle(string value) unique
                 | SetDraftNotes(string value) unique
                 | SetSearch(string value) unique
                 | SetFilter(App.Filter value) unique
                 | CycleDraftPriority unique
                 | ToggleTask(string id) unique
                 | DeleteTask(string id) unique
                 | CycleTaskPriority(string id) unique
                 | SetTaskTitle(string id, string value) unique
                 | SetTaskNotes(string id, string value) unique
        }
    ]]
    return T
end

return M
