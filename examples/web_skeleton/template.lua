local pvm = require("pvm")

local M = {}

local CSS = [=[
:root {
  color-scheme: dark;
  --bg: #0b1020;
  --bg-soft: #121933;
  --panel: rgba(18, 25, 51, 0.78);
  --panel-strong: rgba(22, 32, 65, 0.92);
  --panel-border: rgba(148, 163, 184, 0.14);
  --text: #e5ecff;
  --muted: #96a3c7;
  --line: rgba(148, 163, 184, 0.16);
  --blue: #72a4ff;
  --blue-strong: #5b8dff;
  --green: #5dd4a6;
  --amber: #ffc56a;
  --red: #ff7f96;
  --violet: #aa8cff;
  --shadow: 0 24px 80px rgba(0, 0, 0, 0.34);
  --radius: 22px;
  --radius-sm: 14px;
}

* { box-sizing: border-box; }
html, body { margin: 0; min-height: 100%; }
body {
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
  background:
    radial-gradient(circle at top left, rgba(91, 141, 255, 0.18), transparent 34%),
    radial-gradient(circle at top right, rgba(170, 140, 255, 0.12), transparent 28%),
    linear-gradient(180deg, #0a0f1e 0%, #0b1020 100%);
  color: var(--text);
}

a { color: inherit; text-decoration: none; }
button, input { font: inherit; }

.app-shell {
  max-width: 1200px;
  margin: 0 auto;
  padding: 28px 20px 56px;
}

.topbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
  margin-bottom: 24px;
}

.brand {
  display: flex;
  align-items: center;
  gap: 16px;
}

.brand-mark {
  width: 44px;
  height: 44px;
  border-radius: 14px;
  background: linear-gradient(135deg, var(--blue), var(--violet));
  box-shadow: 0 10px 30px rgba(91, 141, 255, 0.34);
}

.brand-title {
  font-size: 1.05rem;
  font-weight: 800;
  letter-spacing: 0.02em;
}

.brand-subtitle,
.surface-subtitle,
.muted,
.summary-label,
.empty-copy,
.detail-meta,
.field-label,
.panel-copy {
  color: var(--muted);
}

.topbar-links {
  display: flex;
  gap: 10px;
  align-items: center;
  flex-wrap: wrap;
}

.chip,
.path-chip,
.filter-chip,
.priority-pill,
.state-pill,
.user-chip {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  border-radius: 999px;
  padding: 8px 12px;
  border: 1px solid var(--panel-border);
  background: rgba(255, 255, 255, 0.04);
}

.user-chip {
  background: rgba(93, 212, 166, 0.08);
  border-color: rgba(93, 212, 166, 0.18);
}

.surface {
  background: var(--panel);
  border: 1px solid var(--panel-border);
  box-shadow: var(--shadow);
  backdrop-filter: blur(18px);
  border-radius: var(--radius);
}

.hero {
  padding: 28px;
  margin-bottom: 20px;
}

.hero-grid {
  display: grid;
  gap: 24px;
  grid-template-columns: minmax(0, 1.4fr) minmax(280px, 0.9fr);
  align-items: start;
}

.hero-title {
  margin: 0 0 10px;
  font-size: clamp(2rem, 4vw, 3.2rem);
  line-height: 1;
  letter-spacing: -0.04em;
}

.hero-copy {
  max-width: 58ch;
  margin: 0;
  color: var(--muted);
  line-height: 1.65;
}

.summary-grid {
  display: grid;
  gap: 12px;
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.summary-card {
  padding: 16px;
  border-radius: 18px;
  border: 1px solid var(--line);
  background: rgba(255, 255, 255, 0.035);
}

.summary-value {
  font-size: 1.8rem;
  font-weight: 800;
  margin-top: 8px;
}

.summary-card.accent-blue .summary-value { color: var(--blue); }
.summary-card.accent-green .summary-value { color: var(--green); }
.summary-card.accent-amber .summary-value { color: var(--amber); }
.summary-card.accent-violet .summary-value { color: var(--violet); }

.board-layout,
.detail-layout,
.not-found-layout {
  display: grid;
  gap: 20px;
  grid-template-columns: minmax(0, 1fr);
}

.board-toolbar,
.detail-layout {
  grid-template-columns: minmax(0, 1fr) 320px;
  align-items: start;
}

.panel {
  padding: 22px;
}

.panel-title {
  margin: 0 0 8px;
  font-size: 1.15rem;
}

.panel-actions,
.task-card-actions,
.filter-row,
.field-stack,
.inline-actions {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}

.field-stack {
  flex-direction: column;
}

.input {
  width: 100%;
  height: 48px;
  border-radius: 14px;
  border: 1px solid rgba(148, 163, 184, 0.18);
  background: rgba(6, 10, 24, 0.58);
  color: var(--text);
  padding: 0 14px;
  outline: none;
  transition: border-color 140ms ease, box-shadow 140ms ease, transform 140ms ease;
}

.input:focus {
  border-color: rgba(114, 164, 255, 0.62);
  box-shadow: 0 0 0 4px rgba(114, 164, 255, 0.12);
}

.input.notes {
  height: 52px;
}

.btn,
.filter-chip,
.priority-pill {
  cursor: pointer;
  transition: transform 140ms ease, border-color 140ms ease, background 140ms ease;
}

.btn:hover,
.filter-chip:hover,
.priority-pill:hover {
  transform: translateY(-1px);
}

.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 44px;
  padding: 0 16px;
  border-radius: 14px;
  border: 1px solid transparent;
  color: var(--text);
  background: rgba(255, 255, 255, 0.06);
}

.btn-primary {
  background: linear-gradient(135deg, var(--blue), var(--blue-strong));
  box-shadow: 0 12px 30px rgba(91, 141, 255, 0.26);
}

.btn-ghost {
  border-color: var(--line);
}

.btn-danger {
  border-color: rgba(255, 127, 150, 0.26);
  background: rgba(255, 127, 150, 0.08);
  color: #ffd3dc;
}

.btn-success {
  border-color: rgba(93, 212, 166, 0.22);
  background: rgba(93, 212, 166, 0.12);
}

.filter-chip.active {
  background: rgba(114, 164, 255, 0.14);
  border-color: rgba(114, 164, 255, 0.26);
}

.priority-pill.low {
  color: var(--green);
  background: rgba(93, 212, 166, 0.12);
  border-color: rgba(93, 212, 166, 0.18);
}

.priority-pill.medium {
  color: var(--amber);
  background: rgba(255, 197, 106, 0.12);
  border-color: rgba(255, 197, 106, 0.18);
}

.priority-pill.high {
  color: #ffd0db;
  background: rgba(255, 127, 150, 0.12);
  border-color: rgba(255, 127, 150, 0.2);
}

.state-pill.open {
  color: var(--blue);
  border-color: rgba(114, 164, 255, 0.22);
  background: rgba(114, 164, 255, 0.1);
}

.state-pill.done {
  color: var(--green);
  border-color: rgba(93, 212, 166, 0.22);
  background: rgba(93, 212, 166, 0.1);
}

.task-grid {
  display: grid;
  gap: 16px;
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.task-card {
  padding: 18px;
  border-radius: 20px;
  border: 1px solid var(--panel-border);
  background: var(--panel-strong);
  box-shadow: 0 18px 48px rgba(0, 0, 0, 0.22);
}

.task-card.done {
  opacity: 0.86;
}

.task-card.done .task-title-link {
  text-decoration: line-through;
  color: rgba(229, 236, 255, 0.78);
}

.task-card-top {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 14px;
  align-items: center;
}

.task-title-link {
  display: block;
  font-size: 1.08rem;
  font-weight: 700;
  margin-bottom: 10px;
}

.task-notes {
  margin: 0 0 16px;
  color: var(--muted);
  line-height: 1.55;
  min-height: 24px;
}

.empty-state {
  padding: 38px;
  text-align: center;
}

.empty-title {
  margin: 0 0 8px;
  font-size: 1.2rem;
}

.detail-panel,
.side-panel {
  padding: 24px;
}

.detail-head {
  display: flex;
  justify-content: space-between;
  gap: 14px;
  align-items: center;
  margin-bottom: 18px;
}

.detail-title {
  margin: 0;
  font-size: 1.8rem;
}

.field-label {
  font-size: 0.92rem;
  font-weight: 700;
  letter-spacing: 0.02em;
}

.footer-note {
  margin-top: 18px;
  padding-top: 18px;
  border-top: 1px solid var(--line);
  color: var(--muted);
  font-size: 0.94rem;
}

@media (max-width: 960px) {
  .hero-grid,
  .board-toolbar,
  .detail-layout {
    grid-template-columns: minmax(0, 1fr);
  }

  .task-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}

@media (max-width: 640px) {
  .app-shell {
    padding: 18px 14px 40px;
  }

  .hero,
  .panel,
  .detail-panel,
  .side-panel,
  .task-card {
    padding: 18px;
  }

  .summary-grid {
    grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  }

  .topbar {
    align-items: flex-start;
    flex-direction: column;
  }
}
]=]

function M.assets(H, ws_port, opts)
    opts = opts or {}
    local LivePage = require("web").live_page(H, ws_port, opts.live_page_opts)
    return {
        css = CSS,
        client_js = LivePage.client_js,
        bootstrap_js = LivePage.bootstrap_script(opts.path_expr),
    }
end

function M.bind(T, H, F, ws_port, opts)
    opts = opts or {}
    local LivePage = require("web").live_page(H, ws_port, {
        client_js_src = opts.client_js_src,
        bootstrap_js_src = opts.bootstrap_js_src,
    })

    local Low = T.App.Low
    local Medium = T.App.Medium
    local High = T.App.High

    local All = T.App.All
    local Open = T.App.Open
    local Done = T.App.Done

    local function priority_name(priority)
        if priority == Low then
            return "Low"
        end
        if priority == Medium then
            return "Medium"
        end
        return "High"
    end

    local function priority_class(priority)
        if priority == Low then
            return "low"
        end
        if priority == Medium then
            return "medium"
        end
        return "high"
    end

    local function filter_name(filter)
        if filter == Open then
            return "Open"
        end
        if filter == Done then
            return "Done"
        end
        return "All"
    end

    local function text_node(key, class_name, text)
        return H.kel(key, "div", { H.attr("class", class_name) }, { H.text(text) })
    end

    local function summary_card(key, label, value, accent)
        return H.kel(key, "div", { H.attr("class", "summary-card accent-" .. accent) }, {
            H.kel(key .. ":label", "div", { H.attr("class", "summary-label") }, { H.text(label) }),
            H.kel(key .. ":value", "div", { H.attr("class", "summary-value") }, { H.text(tostring(value)) }),
        })
    end

    local function summary_grid(summary)
        return H.kel("summary-grid", "div", { H.attr("class", "summary-grid") }, {
            summary_card("sum-total", "Total tasks", summary.total, "blue"),
            summary_card("sum-open", "Open", summary.open, "green"),
            summary_card("sum-done", "Done", summary.done, "amber"),
            summary_card("sum-high", "High priority", summary.high, "violet"),
        })
    end

    local function nav_bar(nav)
        return H.kel("topbar", "div", { H.attr("class", "topbar") }, {
            H.kel("brand", "div", { H.attr("class", "brand") }, {
                H.kel("brand-mark", "div", { H.attr("class", "brand-mark") }, {}),
                H.kel("brand-copy", "div", {}, {
                    H.kel("brand-title", "div", { H.attr("class", "brand-title") }, { H.text("taskboard") }),
                    H.kel("brand-subtitle", "div", { H.attr("class", "brand-subtitle") }, {
                        H.text("Structural SSR + live patches, with a real app shape")
                    }),
                }),
            }),
            H.kel("topbar-links", "div", { H.attr("class", "topbar-links") }, {
                H.a({ H.href("/"), H.attr("class", "chip") }, { H.text("Board") }),
                H.a({ H.href("/__stats"), H.attr("class", "chip") }, { H.text("Cache stats") }),
                H.kel("path-chip", "span", { H.attr("class", "path-chip") }, { H.text(nav.current_path) }),
                H.kel("user-chip", "span", { H.attr("class", "user-chip") }, {
                    H.text(nav.logged_in and (nav.username or "user") or "guest"),
                }),
            }),
        })
    end

    local function hero(summary)
        return H.kel("hero", "section", { H.attr("class", "hero surface") }, {
            H.kel("hero-grid", "div", { H.attr("class", "hero-grid") }, {
                H.kel("hero-copy", "div", {}, {
                    H.kel("hero-title", "h1", { H.attr("class", "hero-title") }, {
                        H.text("A proper live task app, not just a toy counter")
                    }),
                    H.kel("hero-body", "p", { H.attr("class", "hero-copy") }, {
                        H.text("This example shows real routing, filters, per-connection UI state, typed responses, keyed list patching, inline live editing, and a domain reducer that only recompiles the changed parts.")
                    }),
                }),
                summary_grid(summary),
            }),
        })
    end

    local function filter_button(key, label, active, action, count)
        local class_name = active and "filter-chip active" or "filter-chip"
        return H.kel(key, "button", {
            H.typ("button"),
            H.pvm_action(action),
            H.attr("class", class_name),
        }, {
            H.text(label),
            H.kel(key .. ":count", "span", { H.attr("class", "muted") }, { H.text(tostring(count)) }),
        })
    end

    local function composer(view)
        return H.kel("composer-card", "section", { H.attr("class", "panel surface") }, {
            H.kel("composer-title", "h2", { H.attr("class", "panel-title") }, { H.text("Add a task") }),
            H.kel("composer-copy", "p", { H.attr("class", "panel-copy") }, {
                H.text("Draft inputs are connection-local. One browser can search or draft without disturbing another, while actual task edits broadcast live.")
            }),
            F.live_post("add-task", {}, {
                H.kel("composer-fields", "div", { H.attr("class", "field-stack") }, {
                    H.kel("draft-title-label", "label", { H.attr("class", "field-label") }, { H.text("Title") }),
                    F.live_text_input("draft-title", "draft-title", "draft-title", {
                        H.typ("text"),
                        H.attr("class", "input"),
                        H.attr("placeholder", "Ship the new release board"),
                        H.attr("value", view.draft_title),
                    }),
                    H.kel("draft-notes-label", "label", { H.attr("class", "field-label") }, { H.text("Notes") }),
                    F.live_text_input("draft-notes", "draft-notes", "draft-notes", {
                        H.typ("text"),
                        H.attr("class", "input notes"),
                        H.attr("placeholder", "What good looks like, links, or acceptance criteria"),
                        H.attr("value", view.draft_notes),
                    }),
                }),
                H.kel("composer-actions", "div", { H.attr("class", "panel-actions") }, {
                    H.kel("draft-priority", "button", {
                        H.typ("button"),
                        H.pvm_action("cycle-draft-priority"),
                        H.attr("class", "priority-pill " .. priority_class(view.draft_priority)),
                    }, {
                        H.text("Priority: " .. priority_name(view.draft_priority))
                    }),
                    H.button({ H.typ("submit"), H.attr("class", "btn btn-primary") }, { H.text("Create task") }),
                }),
            }, { key = "composer" }),
        })
    end

    local function board_controls(view)
        local summary = view.summary
        return H.kel("board-controls", "section", { H.attr("class", "panel surface") }, {
            H.kel("board-controls-title", "h2", { H.attr("class", "panel-title") }, { H.text("Find the right slice") }),
            H.kel("board-controls-copy", "p", { H.attr("class", "panel-copy") }, {
                H.text("Search and filters only refresh your current connection. Task mutations update everyone on the board.")
            }),
            H.kel("search-label", "label", { H.attr("class", "field-label") }, { H.text("Search") }),
            F.live_text_input("search", "search", "search", {
                H.typ("text"),
                H.attr("class", "input"),
                H.attr("placeholder", "Search title or notes"),
                H.attr("value", view.search),
            }),
            H.kel("filter-row", "div", { H.attr("class", "filter-row") }, {
                filter_button("filter-all", "All", view.filter == All, "filter-all", summary.total),
                filter_button("filter-open", "Open", view.filter == Open, "filter-open", summary.open),
                filter_button("filter-done", "Done", view.filter == Done, "filter-done", summary.done),
            }),
            H.kel("board-controls-footer", "div", { H.attr("class", "panel-actions") }, {
                H.when(summary.done > 0, H.kel("clear-completed", "button", {
                    H.typ("button"),
                    H.pvm_action("clear-completed"),
                    H.attr("class", "btn btn-danger"),
                }, { H.text("Clear completed") })),
                H.kel("filter-active", "span", { H.attr("class", "chip") }, {
                    H.text("Showing: " .. filter_name(view.filter))
                }),
            }),
        })
    end

    local function task_card(task)
        local key = "task:" .. task.id
        local done = task.done

        return H.kel(key, "article", { H.attr("class", done and "task-card done" or "task-card") }, {
            H.kel(key .. ":top", "div", { H.attr("class", "task-card-top") }, {
                H.kel(key .. ":priority", "button", {
                    H.typ("button"),
                    H.pvm_action("cycle-task-priority"),
                    H.pvm_target(task.id),
                    H.attr("class", "priority-pill " .. priority_class(task.priority)),
                }, {
                    H.text(priority_name(task.priority))
                }),
                H.kel(key .. ":state", "span", {
                    H.attr("class", done and "state-pill done" or "state-pill open")
                }, {
                    H.text(done and "Done" or "Open")
                }),
            }),
            H.a({ H.href("/task/" .. task.id), H.attr("class", "task-title-link") }, {
                H.text(task.title)
            }),
            H.kel(key .. ":notes", "p", { H.attr("class", "task-notes") }, {
                H.text(task.notes ~= "" and task.notes or "No notes yet — click into details and add context live.")
            }),
            H.kel(key .. ":actions", "div", { H.attr("class", "task-card-actions") }, {
                H.kel(key .. ":toggle", "button", {
                    H.typ("button"),
                    H.pvm_action("toggle-task"),
                    H.pvm_target(task.id),
                    H.attr("class", done and "btn btn-success" or "btn btn-ghost"),
                }, {
                    H.text(done and "Reopen" or "Mark done")
                }),
                H.a({ H.href("/task/" .. task.id), H.attr("class", "btn btn-ghost") }, { H.text("Details") }),
                H.kel(key .. ":delete", "button", {
                    H.typ("button"),
                    H.pvm_action("delete-task"),
                    H.pvm_target(task.id),
                    H.attr("class", "btn btn-danger"),
                }, {
                    H.text("Delete")
                }),
            }),
        })
    end

    local function empty_state(view)
        local message = view.search ~= ""
            and ("No tasks match ‘" .. view.search .. "’. Try a broader search or switch filters.")
            or ("No tasks in the “" .. filter_name(view.filter) .. "” slice right now. Add one with the composer above.")

        return H.kel("empty-state", "section", { H.attr("class", "empty-state surface") }, {
            H.kel("empty-title", "h2", { H.attr("class", "empty-title") }, { H.text("Nothing here yet") }),
            H.kel("empty-copy", "p", { H.attr("class", "empty-copy") }, { H.text(message) }),
        })
    end

    local function task_cards(tasks)
        local out = {}
        for i = 1, #tasks do
            out[i] = task_card(tasks[i])
        end
        return out
    end

    local function board(view)
        return H.kel("board-layout", "div", { H.attr("class", "board-layout") }, {
            H.kel("board-toolbar", "div", { H.attr("class", "board-toolbar") }, {
                composer(view),
                board_controls(view),
            }),
            H.when(#view.tasks == 0, empty_state(view)),
            H.when(#view.tasks > 0, H.kel("task-grid", "section", { H.attr("class", "task-grid") }, task_cards(view.tasks))),
        })
    end

    local function detail_page(view)
        local task = view.task
        local key = "detail:" .. task.id
        local done = task.done

        return H.kel("detail-layout", "div", { H.attr("class", "detail-layout") }, {
            H.kel(key, "section", { H.attr("class", "detail-panel surface") }, {
                H.kel(key .. ":head", "div", { H.attr("class", "detail-head") }, {
                    H.kel(key .. ":title-wrap", "div", {}, {
                        H.a({ H.href("/"), H.attr("class", "chip") }, { H.text("← Back to board") }),
                        H.kel(key .. ":title", "h1", { H.attr("class", "detail-title") }, { H.text(task.title) }),
                        H.kel(key .. ":meta", "div", { H.attr("class", "detail-meta") }, {
                            H.text("Task #" .. task.id .. " • " .. (done and "done" or "open") .. " • " .. priority_name(task.priority) .. " priority")
                        }),
                    }),
                    H.kel(key .. ":state", "span", {
                        H.attr("class", done and "state-pill done" or "state-pill open")
                    }, {
                        H.text(done and "Done" or "Open")
                    }),
                }),
                H.kel(key .. ":fields", "div", { H.attr("class", "field-stack") }, {
                    H.kel(key .. ":title-label", "label", { H.attr("class", "field-label") }, { H.text("Title") }),
                    F.live_text_input("detail-title:" .. task.id, "task-title", task.id, {
                        H.typ("text"),
                        H.attr("class", "input"),
                        H.attr("value", task.title),
                    }),
                    H.kel(key .. ":notes-label", "label", { H.attr("class", "field-label") }, { H.text("Notes") }),
                    F.live_text_input("detail-notes:" .. task.id, "task-notes", task.id, {
                        H.typ("text"),
                        H.attr("class", "input notes"),
                        H.attr("value", task.notes),
                        H.attr("placeholder", "Add acceptance notes or links"),
                    }),
                }),
                H.kel(key .. ":actions", "div", { H.attr("class", "inline-actions") }, {
                    H.kel(key .. ":toggle", "button", {
                        H.typ("button"),
                        H.pvm_action("toggle-task"),
                        H.pvm_target(task.id),
                        H.attr("class", done and "btn btn-success" or "btn btn-ghost"),
                    }, {
                        H.text(done and "Reopen task" or "Mark done")
                    }),
                    H.kel(key .. ":priority", "button", {
                        H.typ("button"),
                        H.pvm_action("cycle-task-priority"),
                        H.pvm_target(task.id),
                        H.attr("class", "priority-pill " .. priority_class(task.priority)),
                    }, {
                        H.text("Priority: " .. priority_name(task.priority))
                    }),
                    H.kel(key .. ":delete", "button", {
                        H.typ("button"),
                        H.pvm_action("delete-task"),
                        H.pvm_target(task.id),
                        H.attr("class", "btn btn-danger"),
                    }, {
                        H.text("Delete task")
                    }),
                }),
                H.kel(key .. ":footer", "div", { H.attr("class", "footer-note") }, {
                    H.text("Title and notes update the shared task tree live. Open the board in another browser and you will see patches land immediately.")
                }),
            }),
            H.kel("detail-side", "aside", { H.attr("class", "side-panel surface") }, {
                H.kel("detail-side-title", "h2", { H.attr("class", "panel-title") }, { H.text("Workspace snapshot") }),
                H.kel("detail-side-copy", "p", { H.attr("class", "panel-copy") }, {
                    H.text("The side panel is just another keyed HTML subtree. Small count changes become tiny text patches instead of a full rerender.")
                }),
                summary_grid(view.summary),
            }),
        })
    end

    local function not_found(view)
        return H.kel("not-found-layout", "div", { H.attr("class", "not-found-layout") }, {
            H.kel("not-found-panel", "section", { H.attr("class", "detail-panel surface") }, {
                H.kel("not-found-title", "h1", { H.attr("class", "detail-title") }, { H.text("Route not found") }),
                H.kel("not-found-copy", "p", { H.attr("class", "panel-copy") }, {
                    H.text("There is no page for " .. view.path .. ". The live app still keeps its global task summary ready below.")
                }),
                H.a({ H.href("/"), H.attr("class", "btn btn-primary") }, { H.text("Back to board") }),
            }),
            H.kel("not-found-side", "aside", { H.attr("class", "side-panel surface") }, {
                H.kel("not-found-side-title", "h2", { H.attr("class", "panel-title") }, { H.text("Current task counts") }),
                summary_grid(view.summary),
            }),
        })
    end

    local function shell(nav, title, content)
        return LivePage.shell(title, {
            H.kel("app-shell", "div", { H.attr("class", "app-shell") }, {
                nav_bar(nav),
                content,
            }),
        }, {
            body_attrs = { H.attr("class", "app-body") },
            head_children = opts.stylesheet_href and {
                H.kel("viewport-meta", "meta", {
                    H.attr("name", "viewport"),
                    H.attr("content", "width=device-width, initial-scale=1"),
                }, {}),
                H.kel("page-style-link", "link", {
                    H.rel("stylesheet"),
                    H.href(opts.stylesheet_href),
                }, {}),
            } or {
                H.kel("viewport-meta", "meta", {
                    H.attr("name", "viewport"),
                    H.attr("content", "width=device-width, initial-scale=1"),
                }, {}),
                H.kel("page-style", "style", {}, { H.raw(CSS) }),
            },
        })
    end

    return pvm.phase("web.skeleton.template", {
        [T.Page.Home] = function(self)
            return pvm.once(shell(self.nav, "taskboard", H.kel("home", "main", {}, {
                hero(self.summary),
                board(self),
            })))
        end,

        [T.Page.TaskDetail] = function(self)
            return pvm.once(shell(self.nav, self.task.title, H.kel("detail", "main", {}, {
                hero(self.summary),
                detail_page(self),
            })))
        end,

        [T.Page.NotFound] = function(self)
            return pvm.once(shell(self.nav, "Not found", H.kel("not-found", "main", {}, {
                hero(self.summary),
                not_found(self),
            })))
        end,
    })
end

return M
