export const DEFAULT_UI = Object.freeze({
  search: "",
  filter: "all",
  draftTitle: "",
  draftNotes: "",
  draftPriority: "medium",
})

const FILTERS = new Set(["all", "open", "done"])
const PRIORITIES = new Set(["low", "medium", "high"])

export function initialState() {
  return {
    nextId: 4,
    tasks: [
      {
        id: "1",
        title: "Ship Bun baseline demo",
        notes: "Build the same taskboard in an idiomatic Bun style with plain templates and websocket fragment replacement.",
        priority: "high",
        done: false,
      },
      {
        id: "2",
        title: "Keep the UI polished",
        notes: "Use real CSS, responsive cards, filters, and a detail page so the comparison stays honest.",
        priority: "medium",
        done: false,
      },
      {
        id: "3",
        title: "Compare the architecture",
        notes: "This version intentionally rerenders a big fragment per update instead of doing keyed structural patches.",
        priority: "low",
        done: true,
      },
    ],
  }
}

export function normalizeUi(ui = {}) {
  const filter = FILTERS.has(ui.filter) ? ui.filter : DEFAULT_UI.filter
  const draftPriority = PRIORITIES.has(ui.draftPriority) ? ui.draftPriority : DEFAULT_UI.draftPriority
  return {
    search: String(ui.search ?? DEFAULT_UI.search),
    filter,
    draftTitle: String(ui.draftTitle ?? DEFAULT_UI.draftTitle),
    draftNotes: String(ui.draftNotes ?? DEFAULT_UI.draftNotes),
    draftPriority,
  }
}

function cloneUi(ui) {
  return { ...normalizeUi(ui) }
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
}

function escapeAttr(value) {
  return escapeHtml(value).replaceAll('"', '&quot;')
}

function trimText(value) {
  return String(value ?? "").trim()
}

function nextPriority(priority) {
  if (priority === "low") return "medium"
  if (priority === "medium") return "high"
  return "low"
}

function priorityLabel(priority) {
  if (priority === "low") return "Low"
  if (priority === "medium") return "Medium"
  return "High"
}

function filterLabel(filter) {
  if (filter === "open") return "Open"
  if (filter === "done") return "Done"
  return "All"
}

function summaryOf(tasks) {
  let open = 0
  let done = 0
  let high = 0
  for (const task of tasks) {
    if (task.done) done++
    else open++
    if (task.priority === "high") high++
  }
  return {
    total: tasks.length,
    open,
    done,
    high,
  }
}

function visibleTasks(tasks, ui) {
  const needle = ui.search.trim().toLowerCase()
  return tasks.filter((task) => {
    const passesFilter =
      ui.filter === "all" ||
      (ui.filter === "open" && !task.done) ||
      (ui.filter === "done" && task.done)

    if (!passesFilter) return false
    if (needle === "") return true

    const haystack = `${task.title} ${task.notes}`.toLowerCase()
    return haystack.includes(needle)
  })
}

function findTask(tasks, id) {
  return tasks.find((task) => task.id === id) ?? null
}

function updateTask(tasks, id, updater) {
  let changed = false
  const next = tasks.map((task) => {
    if (task.id !== id) return task
    const updated = updater(task)
    if (updated !== task) changed = true
    return updated
  })
  return changed ? next : tasks
}

function deleteTask(tasks, id) {
  const next = tasks.filter((task) => task.id !== id)
  return next.length === tasks.length ? tasks : next
}

function clearCompleted(tasks) {
  const next = tasks.filter((task) => !task.done)
  return next.length === tasks.length ? tasks : next
}

function addTask(state, ui) {
  const id = String(state.nextId)
  const notes = trimText(ui.draftNotes)
  let title = trimText(ui.draftTitle)
  if (title === "") title = notes !== "" ? notes : `Task ${id}`

  return {
    nextId: state.nextId + 1,
    tasks: state.tasks.concat({
      id,
      title,
      notes,
      priority: ui.draftPriority,
      done: false,
    }),
  }
}

function titleForDetail(state, path) {
  const match = path.match(/^\/task\/([^/]+)$/)
  if (!match) return null
  const task = findTask(state.tasks, match[1])
  return task ? task.title : "Not found"
}

export function pageTitle(state, path) {
  if (path === "/") return "taskboard · Bun baseline"
  if (path === "/__stats") return "stats · Bun baseline"
  const detail = titleForDetail(state, path)
  if (detail) return `${detail} · Bun baseline`
  return "Not found · Bun baseline"
}

function metricCard(accent, label, value) {
  return `
    <div class="summary-card accent-${accent}">
      <div class="summary-label">${escapeHtml(label)}</div>
      <div class="summary-value">${escapeHtml(value)}</div>
    </div>
  `
}

function summaryGrid(summary) {
  return `
    <div class="summary-grid">
      ${metricCard("blue", "Total tasks", summary.total)}
      ${metricCard("green", "Open", summary.open)}
      ${metricCard("amber", "Done", summary.done)}
      ${metricCard("violet", "High priority", summary.high)}
    </div>
  `
}

function navBar(path) {
  return `
    <div class="topbar">
      <div class="brand">
        <div class="brand-mark"></div>
        <div>
          <div class="brand-title">taskboard</div>
          <div class="brand-subtitle">Idiomatic Bun baseline: plain templates + fragment rerender</div>
        </div>
      </div>
      <div class="topbar-links">
        <a class="chip" href="/">Board</a>
        <a class="chip" href="/__stats">Server stats</a>
        <span class="path-chip">${escapeHtml(path)}</span>
        <span class="user-chip">cedric</span>
      </div>
    </div>
  `
}

function hero(summary) {
  return `
    <section class="hero surface">
      <div class="hero-grid">
        <div>
          <h1 class="hero-title">A realistic Bun baseline for the same taskboard</h1>
          <p class="hero-copy">
            This version uses plain JavaScript objects, server-side template strings, and websocket-driven
            replacement of a large HTML fragment. That is much closer to what a normal Bun developer might write.
          </p>
        </div>
        ${summaryGrid(summary)}
      </div>
    </section>
  `
}

function composer(ui) {
  return `
    <section class="panel surface">
      <h2 class="panel-title">Add a task</h2>
      <p class="panel-copy">
        Draft fields, search, and filters are per-connection. Shared task edits broadcast by rerendering the main app fragment.
      </p>
      <form data-action="add-task" class="field-stack">
        <label class="field-label" for="draft-title">Title</label>
        <input id="draft-title" class="input" data-live="input" data-action="draft-title" type="text" placeholder="Ship the baseline" value="${escapeAttr(ui.draftTitle)}">
        <label class="field-label" for="draft-notes">Notes</label>
        <input id="draft-notes" class="input notes" data-live="input" data-action="draft-notes" type="text" placeholder="Feature notes or acceptance criteria" value="${escapeAttr(ui.draftNotes)}">
        <div class="panel-actions">
          <button type="button" class="priority-pill ${escapeAttr(ui.draftPriority)}" data-action="cycle-draft-priority">
            Priority: ${escapeHtml(priorityLabel(ui.draftPriority))}
          </button>
          <button type="submit" class="btn btn-primary">Create task</button>
        </div>
      </form>
    </section>
  `
}

function filterButton(key, label, active, action, count) {
  return `
    <button id="${escapeAttr(key)}" type="button" class="filter-chip${active ? " active" : ""}" data-action="${escapeAttr(action)}">
      ${escapeHtml(label)} <span class="muted">${escapeHtml(count)}</span>
    </button>
  `
}

function boardControls(ui, summary) {
  return `
    <section class="panel surface">
      <h2 class="panel-title">Find the right slice</h2>
      <p class="panel-copy">
        This baseline refreshes the whole <code>#app-root</code> fragment for the active page instead of sending tiny keyed DOM patches.
      </p>
      <label class="field-label" for="search">Search</label>
      <input id="search" class="input" data-live="input" data-action="search" type="text" placeholder="Search title or notes" value="${escapeAttr(ui.search)}">
      <div class="filter-row">
        ${filterButton("filter-all", "All", ui.filter === "all", "filter-all", summary.total)}
        ${filterButton("filter-open", "Open", ui.filter === "open", "filter-open", summary.open)}
        ${filterButton("filter-done", "Done", ui.filter === "done", "filter-done", summary.done)}
      </div>
      <div class="panel-actions">
        ${summary.done > 0 ? `<button type="button" class="btn btn-danger" data-action="clear-completed">Clear completed</button>` : ""}
        <span class="chip">Showing: ${escapeHtml(filterLabel(ui.filter))}</span>
      </div>
    </section>
  `
}

function taskCard(task) {
  const noteText = task.notes || "No notes yet — click into details and edit live."
  return `
    <article class="task-card${task.done ? " done" : ""}">
      <div class="task-card-top">
        <button type="button" class="priority-pill ${escapeAttr(task.priority)}" data-action="cycle-task-priority" data-target-id="${escapeAttr(task.id)}">
          ${escapeHtml(priorityLabel(task.priority))}
        </button>
        <span class="state-pill ${task.done ? "done" : "open"}">${task.done ? "Done" : "Open"}</span>
      </div>
      <a class="task-title-link" href="/task/${encodeURIComponent(task.id)}">${escapeHtml(task.title)}</a>
      <p class="task-notes">${escapeHtml(noteText)}</p>
      <div class="task-card-actions">
        <button type="button" class="btn ${task.done ? "btn-success" : "btn-ghost"}" data-action="toggle-task" data-target-id="${escapeAttr(task.id)}">
          ${task.done ? "Reopen" : "Mark done"}
        </button>
        <a class="btn btn-ghost" href="/task/${encodeURIComponent(task.id)}">Details</a>
        <button type="button" class="btn btn-danger" data-action="delete-task" data-target-id="${escapeAttr(task.id)}">Delete</button>
      </div>
    </article>
  `
}

function emptyState(ui) {
  const text = ui.search.trim() !== ""
    ? `No tasks match “${ui.search}”. Try a broader search or a different filter.`
    : `No tasks in the “${filterLabel(ui.filter)}” slice right now. Add one with the composer above.`

  return `
    <section class="empty-state surface">
      <h2 class="empty-title">Nothing here yet</h2>
      <p class="empty-copy">${escapeHtml(text)}</p>
    </section>
  `
}

function boardPage(state, ui, summary) {
  const tasks = visibleTasks(state.tasks, ui)
  return `
    <main>
      ${hero(summary)}
      <div class="board-layout">
        <div class="board-toolbar">
          ${composer(ui)}
          ${boardControls(ui, summary)}
        </div>
        ${tasks.length === 0 ? emptyState(ui) : `
          <section class="task-grid">
            ${tasks.map(taskCard).join("")}
          </section>
        `}
      </div>
    </main>
  `
}

function detailPage(state, path, summary) {
  const match = path.match(/^\/task\/([^/]+)$/)
  const task = match ? findTask(state.tasks, match[1]) : null
  if (!task) return notFoundPage(path, summary)

  return `
    <main>
      ${hero(summary)}
      <div class="detail-layout">
        <section class="detail-panel surface">
          <div class="detail-head">
            <div>
              <a class="chip" href="/">← Back to board</a>
              <h1 class="detail-title">${escapeHtml(task.title)}</h1>
              <div class="detail-meta">Task #${escapeHtml(task.id)} • ${task.done ? "done" : "open"} • ${escapeHtml(priorityLabel(task.priority))} priority</div>
            </div>
            <span class="state-pill ${task.done ? "done" : "open"}">${task.done ? "Done" : "Open"}</span>
          </div>
          <div class="field-stack">
            <label class="field-label" for="task-title">Title</label>
            <input id="task-title" class="input" data-live="input" data-action="task-title" data-target-id="${escapeAttr(task.id)}" type="text" value="${escapeAttr(task.title)}">
            <label class="field-label" for="task-notes">Notes</label>
            <input id="task-notes" class="input notes" data-live="input" data-action="task-notes" data-target-id="${escapeAttr(task.id)}" type="text" value="${escapeAttr(task.notes)}" placeholder="Add acceptance notes or links">
          </div>
          <div class="inline-actions">
            <button type="button" class="btn ${task.done ? "btn-success" : "btn-ghost"}" data-action="toggle-task" data-target-id="${escapeAttr(task.id)}">
              ${task.done ? "Reopen task" : "Mark done"}
            </button>
            <button type="button" class="priority-pill ${escapeAttr(task.priority)}" data-action="cycle-task-priority" data-target-id="${escapeAttr(task.id)}">
              Priority: ${escapeHtml(priorityLabel(task.priority))}
            </button>
            <button type="button" class="btn btn-danger" data-action="delete-task" data-target-id="${escapeAttr(task.id)}">Delete task</button>
          </div>
          <div class="footer-note">
            Every shared change rerenders the full app fragment for each connected client. This is a simple, realistic baseline strategy.
          </div>
        </section>
        <aside class="side-panel surface">
          <h2 class="panel-title">Workspace snapshot</h2>
          <p class="panel-copy">The Bun baseline keeps the browser logic small, but it trades away fine-grained structural patching.</p>
          ${summaryGrid(summary)}
        </aside>
      </div>
    </main>
  `
}

function notFoundPage(path, summary) {
  return `
    <main>
      ${hero(summary)}
      <div class="not-found-layout">
        <section class="detail-panel surface">
          <h1 class="detail-title">Route not found</h1>
          <p class="panel-copy">There is no page for ${escapeHtml(path)}.</p>
          <a class="btn btn-primary" href="/">Back to board</a>
        </section>
        <aside class="side-panel surface">
          <h2 class="panel-title">Current task counts</h2>
          ${summaryGrid(summary)}
        </aside>
      </div>
    </main>
  `
}

export function renderAppRoot({ state, path, ui }) {
  const normalizedUi = normalizeUi(ui)
  const summary = summaryOf(state.tasks)

  let content = ""
  if (path === "/") content = boardPage(state, normalizedUi, summary)
  else if (path === "/__stats") content = notFoundPage(path, summary)
  else if (/^\/task\/[^/]+$/.test(path)) content = detailPage(state, path, summary)
  else content = notFoundPage(path, summary)

  return `
    <div id="app-root" class="app-shell">
      ${navBar(path)}
      ${content}
    </div>
  `
}

export function renderPage({ state, path, ui }) {
  const title = pageTitle(state, path)
  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapeHtml(title)}</title>
    <link rel="stylesheet" href="/styles.css">
  </head>
  <body>
    ${renderAppRoot({ state, path, ui })}
    <script src="/client.js"></script>
    <script>window.BunTaskboard.connect()</script>
  </body>
</html>`
}

export function statsText({ state, connections }) {
  const summary = summaryOf(state.tasks)
  return [
    `bun_taskboard`,
    `tasks=${summary.total}`,
    `open=${summary.open}`,
    `done=${summary.done}`,
    `high=${summary.high}`,
    `connections=${connections.size}`,
    `render_strategy=full_fragment_replace`,
    `client_runtime=tiny_capture_and_swap`,
  ].join("\n") + "\n"
}

export function applyClientMessage(state, ui, msg) {
  const nextUi = cloneUi(ui)

  if (msg && msg.type === "input") {
    if (msg.action === "draft-title") {
      nextUi.draftTitle = String(msg.value ?? "")
      return { state, ui: nextUi, refresh: true, broadcast: false }
    }
    if (msg.action === "draft-notes") {
      nextUi.draftNotes = String(msg.value ?? "")
      return { state, ui: nextUi, refresh: true, broadcast: false }
    }
    if (msg.action === "search") {
      nextUi.search = String(msg.value ?? "")
      return { state, ui: nextUi, refresh: true, broadcast: false }
    }
    if (msg.action === "task-title" && msg.target_id) {
      const title = trimText(msg.value)
      const tasks = updateTask(state.tasks, msg.target_id, (task) => {
        if (title === "" || title === task.title) return task
        return { ...task, title }
      })
      return { state: tasks === state.tasks ? state : { ...state, tasks }, ui: nextUi, refresh: false, broadcast: tasks !== state.tasks }
    }
    if (msg.action === "task-notes" && msg.target_id) {
      const notes = String(msg.value ?? "")
      const tasks = updateTask(state.tasks, msg.target_id, (task) => {
        if (notes === task.notes) return task
        return { ...task, notes }
      })
      return { state: tasks === state.tasks ? state : { ...state, tasks }, ui: nextUi, refresh: false, broadcast: tasks !== state.tasks }
    }
  }

  if (msg && msg.type === "submit" && msg.action === "add-task") {
    const nextState = addTask(state, nextUi)
    nextUi.draftTitle = ""
    nextUi.draftNotes = ""
    return { state: nextState, ui: nextUi, refresh: false, broadcast: true }
  }

  if (msg && msg.type === "click") {
    if (msg.action === "cycle-draft-priority") {
      nextUi.draftPriority = nextPriority(nextUi.draftPriority)
      return { state, ui: nextUi, refresh: true, broadcast: false }
    }
    if (msg.action === "filter-all") {
      nextUi.filter = "all"
      return { state, ui: nextUi, refresh: true, broadcast: false }
    }
    if (msg.action === "filter-open") {
      nextUi.filter = "open"
      return { state, ui: nextUi, refresh: true, broadcast: false }
    }
    if (msg.action === "filter-done") {
      nextUi.filter = "done"
      return { state, ui: nextUi, refresh: true, broadcast: false }
    }
    if (msg.action === "clear-completed") {
      const tasks = clearCompleted(state.tasks)
      return { state: tasks === state.tasks ? state : { ...state, tasks }, ui: nextUi, refresh: false, broadcast: tasks !== state.tasks }
    }
    if (msg.action === "toggle-task" && msg.target_id) {
      const tasks = updateTask(state.tasks, msg.target_id, (task) => ({ ...task, done: !task.done }))
      return { state: tasks === state.tasks ? state : { ...state, tasks }, ui: nextUi, refresh: false, broadcast: tasks !== state.tasks }
    }
    if (msg.action === "delete-task" && msg.target_id) {
      const tasks = deleteTask(state.tasks, msg.target_id)
      return { state: tasks === state.tasks ? state : { ...state, tasks }, ui: nextUi, refresh: false, broadcast: tasks !== state.tasks }
    }
    if (msg.action === "cycle-task-priority" && msg.target_id) {
      const tasks = updateTask(state.tasks, msg.target_id, (task) => ({ ...task, priority: nextPriority(task.priority) }))
      return { state: tasks === state.tasks ? state : { ...state, tasks }, ui: nextUi, refresh: false, broadcast: tasks !== state.tasks }
    }
  }

  return { state, ui: nextUi, refresh: false, broadcast: false }
}
