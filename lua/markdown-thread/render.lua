-- Buffer documents (parsed, cached per changedtick) and render-markdown
-- marks. render-markdown calls a custom handler with ctx = { buf, root } and
-- expects { conceal, start_row, start_col, opts } marks; conceal = true marks
-- are hidden on the cursor line like render-markdown's own.
local P = require("markdown-thread.parser")
local C = require("markdown-thread.config")

local M = {}

local cache = {}

--- Parsed document for a buffer, reparsed when the buffer changed.
function M.document(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local c = cache[buf]
  if c and c.tick == tick then
    return c.doc
  end
  local doc = P.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  cache[buf] = { tick = tick, doc = doc }
  return doc
end

function M.forget(buf)
  cache[buf] = nil
end

--- "2026-10-06T19:57-04:00" -> "2026-10-06 19:57"
function M.short_time(ts)
  if not ts then
    return nil
  end
  local d, t = ts:match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)")
  return d and (d .. " " .. t) or ts
end

local function state_of(t)
  return t.duplicate and "duplicate" or P.state(t)
end

local function chip(m, icons, opts)
  local parts
  if m.kind == "close" then
    parts = { { icons.closed .. "closed", "MdThreadClosed" } }
    if m.name then
      parts[#parts + 1] = { " · " .. m.name, "MdThreadMeta" }
    end
    if m.timestamp then
      parts[#parts + 1] = { " · " .. M.short_time(m.timestamp), "MdThreadMeta" }
    end
    if m.reason then
      parts[#parts + 1] = { " · " .. m.reason, "MdThreadMeta" }
    end
    return parts
  end
  local responder = m.kind == "responder"
  local who = m.name or (responder and "responder" or opts.annotator_label)
  parts = {
    { (responder and icons.responder or icons.annotator) .. who,
      responder and "MdThreadResponder" or "MdThreadAnnotator" },
  }
  if m.timestamp then
    parts[#parts + 1] = { "  " .. M.short_time(m.timestamp), "MdThreadMeta" }
  end
  return parts
end

--- Marks for render-markdown's custom handler (markdown language).
function M.marks(ctx)
  local opts = C.options
  if not opts.render.enabled then
    return {}
  end
  -- render-markdown also calls markdown handlers for injected markdown
  -- (```markdown blocks); only the buffer's own tree starts at row 0.
  if ctx.root and ctx.root.range then
    local r = ctx.root:range()
    if r ~= 0 then
      return {}
    end
  end
  local buf = ctx.buf
  local doc = M.document(buf)
  local icons = opts.icons
  local marks = {}
  local function add(conceal, row, col, o)
    marks[#marks + 1] = { conceal = conceal, start_row = row, start_col = col, opts = o }
  end
  local function badge(start_off, end_off, text, hl)
    local s, e = doc:pos(start_off), doc:pos(end_off)
    add(true, s[1] - 1, s[2], { end_row = e[1] - 1, end_col = e[2], conceal = "" })
    add(true, s[1] - 1, s[2], { virt_text = { { text, hl } }, virt_text_pos = "inline" })
  end
  for _, t in ipairs(doc.threads) do
    local state = state_of(t)
    local shl = C.state_hl[state]
    if opts.render.tint then
      for row = t.start, t["end"] do
        add(false, row - 1, 0, { line_hl_group = "MdThreadLine" })
      end
    end
    -- header: [?label] -> badge "label · state"
    add(true, t.start - 1, t.header_col, { end_col = t.header_end, conceal = "" })
    add(true, t.start - 1, t.header_col, {
      virt_text = { { icons.thread .. t.label, "MdThreadLabel" }, { " · " .. state, shl } },
      virt_text_pos = "inline",
    })
    -- marker lines -> chips
    for _, m in ipairs(t.messages) do
      if m.kind ~= "opener" then
        local col = t.content_col[m.row]
        local line = doc.lines[m.row]
        add(true, m.row - 1, col, { end_col = #line, conceal = "" })
        add(true, m.row - 1, col, { virt_text = chip(m, icons, opts), virt_text_pos = "inline" })
      end
    end
    for _, a in ipairs(t.anchors) do
      badge(a.start, a["end"], icons.anchor .. a.label, shl)
    end
  end
  for _, o in ipairs(doc.orphans) do
    badge(o.start, o["end"], icons.anchor .. o.label .. "?", "MdThreadOrphan")
  end
  return marks
end

return M
