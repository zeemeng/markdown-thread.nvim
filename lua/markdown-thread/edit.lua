-- Editing: new threads and anchors, follow-ups, closing, Enter on an empty
-- quote line inside a thread, navigation, lists and diagnostics.
local P = require("markdown-thread.parser")
local R = require("markdown-thread.render")
local C = require("markdown-thread.config")

local api = vim.api
local M = {}

local function notify(msg, level)
  vim.notify("markdown-thread: " .. msg, level or vim.log.levels.INFO)
end

--- Timestamp for the user's own markers, per config.timestamp.
function M.user_timestamp(kind)
  kind = kind or C.options.timestamp
  if kind == "date" then
    return os.date("%Y-%m-%d")
  elseif kind == "datetime" then
    local z = os.date("%z") -- +HHMM
    return os.date("%Y-%m-%dT%H:%M") .. z:sub(1, 3) .. ":" .. z:sub(4, 5)
  end
  return nil
end

--- `fields` overrides the configured name/time: { name = ..., timestamp = ... }
--- (false = none).
local function marker_line(marker, reason, fields)
  local s = marker
  local name, ts = C.options.author, M.user_timestamp()
  if fields then
    if fields.name ~= nil then
      name = fields.name or nil
    end
    if fields.timestamp ~= nil then
      ts = fields.timestamp or nil
    end
  end
  if name and name ~= "" then
    s = s .. " " .. name
  end
  if ts then
    s = s .. " @ " .. ts
  end
  if reason and reason ~= "" then
    s = s .. " ! " .. reason
  end
  return s
end

local function content_blank(doc, row)
  local e = P.quote_match(doc.lines[row])
  return e ~= nil and P.is_blank(doc.lines[row]:sub(e))
end

--- Append content lines to the end of thread t (buffer rows are 1-based in t).
--- Returns the row of the last inserted line.
local function append(buf, doc, t, contents)
  local lines = {}
  if not content_blank(doc, t["end"]) then
    lines[#lines + 1] = t.prefix
  end
  for _, c in ipairs(contents) do
    lines[#lines + 1] = c == "" and t.prefix or (t.prefix .. " " .. c)
  end
  api.nvim_buf_set_lines(buf, t["end"], t["end"], true, lines)
  return t["end"] + #lines
end

local function current_thread()
  local buf = api.nvim_get_current_buf()
  local doc = R.document(buf)
  local row = api.nvim_win_get_cursor(0)[1]
  return buf, doc, doc:thread_at(row)
end

--- Start a follow-up (`-->`) at the end of the thread under the cursor.
function M.followup()
  local buf, doc, t = current_thread()
  if not t then
    return notify("cursor is not in a thread", vim.log.levels.WARN)
  end
  local last = append(buf, doc, t, { marker_line("-->"), "" })
  -- the empty content line holds the cursor: "> " with the trailing space
  api.nvim_buf_set_lines(buf, last - 1, last, true, { t.prefix .. " " })
  api.nvim_win_set_cursor(0, { last, #t.prefix + 1 })
  vim.cmd("startinsert!")
end

--- Close the thread under the cursor with a `+++` line.
function M.close(reason, fields)
  local buf, doc, t = current_thread()
  if not t then
    return notify("cursor is not in a thread", vim.log.levels.WARN)
  end
  if P.state(t) == "closed" then
    return notify("thread [?" .. t.label .. "] is already closed", vim.log.levels.WARN)
  end
  if reason and reason:find("\n") then
    return notify("a close reason is one line", vim.log.levels.ERROR)
  end
  local last = append(buf, doc, t, { marker_line("+++", reason, fields) })
  api.nvim_win_set_cursor(0, { last, 0 })
end

--- Enter on an empty `> ` line of a thread (insert mode). Keeps the thread:
--- the line becomes a blank `>` line and a new `> ` line follows. Enter on
--- a second empty line in a row ends the thread: both lines become a blank
--- separator and an empty line for the cursor. Returns true when handled.
function M.empty_quote_enter()
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1]
  local doc = R.document(buf)
  local t = doc:thread_at(row)
  if not t or row == t.start then
    return false
  end
  local line = doc.lines[row]
  local e = P.quote_match(line)
  if not e or not P.is_blank(line:sub(e)) then
    return false
  end
  if row - 1 > t.start and content_blank(doc, row - 1) then
    -- end the thread: a blank separator, then the line to type on (text
    -- right under a thread would continue the quote in CommonMark)
    api.nvim_buf_set_lines(buf, row - 2, row, true, { "", "" })
    api.nvim_win_set_cursor(0, { row, 0 })
    return true
  end
  api.nvim_buf_set_lines(buf, row - 1, row, true, { t.prefix, t.prefix .. " " })
  api.nvim_win_set_cursor(0, { row + 1, #t.prefix + 1 })
  return true
end

--- Jump to the next/previous thread header (optionally only open ones).
function M.jump(dir, open_only)
  local doc = R.document(0)
  local row = api.nvim_win_get_cursor(0)[1]
  local best
  for _, t in ipairs(doc.threads) do
    if not open_only or P.state(t) == "open" then
      if dir > 0 and t.start > row and (not best or t.start < best) then
        best = t.start
      elseif dir < 0 and t.start < row and (not best or t.start > best) then
        best = t.start
      end
    end
  end
  if not best then
    return notify("no " .. (open_only and "open " or "") .. "thread " .. (dir > 0 and "below" or "above"))
  end
  vim.cmd("normal! m'")
  api.nvim_win_set_cursor(0, { best, 0 })
end

--- Threads as location-list items (state filter optional).
function M.items(buf, state)
  local doc = R.document(buf)
  local items = {}
  for _, t in ipairs(doc.threads) do
    local st = t.duplicate and "duplicate" or P.state(t)
    if not state or state == "all" or state == st then
      local first = t.messages[1] and t.messages[1].kind == "opener" and t.messages[1].body[1] or ""
      items[#items + 1] = {
        bufnr = buf,
        lnum = t.start,
        col = 1,
        text = ("[%s] %s%s"):format(st, t.label, first ~= "" and (": " .. first) or ""),
        type = st == "open" and "W" or (st == "duplicate" and "E" or "I"),
      }
    end
  end
  return items
end

function M.list(state)
  local buf = api.nvim_get_current_buf()
  local items = M.items(buf, state)
  vim.fn.setloclist(0, {}, " ", { title = "markdown threads" .. (state and (" (" .. state .. ")") or ""), items = items })
  if #items == 0 then
    return notify("no threads")
  end
  vim.cmd("lopen")
end

M.ns = api.nvim_create_namespace("markdown-thread")

--- Parser diagnostics into vim.diagnostic.
function M.check(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  local doc = R.document(buf)
  local out = {}
  for _, d in ipairs(doc.diagnostics) do
    out[#out + 1] = {
      lnum = d.line - 1,
      col = 0,
      severity = d.severity == "error" and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
      message = d.message,
      code = d.code,
      source = "markdown-thread",
    }
  end
  vim.diagnostic.set(M.ns, buf, out)
  return out
end

---------------------------------------------------------------------------
-- new threads and anchors

local function valid_label(label)
  if not label or P.label_key(label) == "" then
    return nil, "empty label"
  end
  if label:find("[%[%]]") then
    return nil, "labels cannot contain [ or ]"
  end
  return true
end

--- Row (1-based) after which a new thread goes, and its indent, for an
--- anchor on `row`: after the paragraph (or list-item paragraph); after the
--- whole block quote for anchors in ordinary quotes.
function M.placement(doc, row)
  local lines = doc.lines
  local function blank(r)
    return P.is_blank(lines[r] or "")
  end
  if P.quote_match(lines[row]) then
    local e, ws = P.quote_match(lines[row])
    local last = row
    while lines[last + 1] and P.quote_match(lines[last + 1]) do
      last = last + 1
    end
    return last, ws
  end
  local function item_indent(l)
    local lead = l:match("^(%s*[-*+]%s+)") or l:match("^(%s*%d+[.)]%s+)")
    return lead and #lead
  end
  -- start of the paragraph: walk up over non-blank lines until a list item
  local first = row
  while first > 1 and not blank(first - 1) and not item_indent(lines[first])
    and doc.kind[first - 1] == "body" and not P.quote_match(lines[first - 1]) do
    first = first - 1
  end
  local indent = item_indent(lines[first])
  indent = indent and string.rep(" ", indent) or lines[first]:match("^%s*")
  local last = row
  while lines[last + 1] and not blank(last + 1) and not item_indent(lines[last + 1])
    and doc.kind[last + 1] == "body" and not P.quote_match(lines[last + 1])
    and not lines[last + 1]:find("^%s*#") do
    last = last + 1
  end
  return last, indent
end

local function insert_thread(buf, doc, row, label)
  local last, indent = M.placement(doc, row)
  local header = indent .. "> [?" .. label .. "] "
  local lines = { "", header }
  local nxt = doc.lines[last + 1]
  if nxt and not P.is_blank(nxt) then
    lines[#lines + 1] = ""
  end
  api.nvim_buf_set_lines(buf, last, last, true, lines)
  api.nvim_win_set_cursor(0, { last + 2, #header })
  vim.cmd("startinsert!")
end

local function with_label(opts, fn)
  if opts.label then
    return fn(opts.label)
  end
  vim.ui.input({ prompt = "Thread label: " }, function(input)
    if input then
      fn(input)
    end
  end)
end

--- New anchor (and thread, unless the label already has one).
--- opts.range = { srow, scol, erow, ecol } (1-based rows, 0-based byte cols,
--- end inclusive) anchors a highlight; otherwise a point anchor goes after
--- the word under the cursor. opts.label skips the prompt.
function M.new(opts)
  opts = opts or {}
  local buf = api.nvim_get_current_buf()
  local doc = R.document(buf)
  local cur = api.nvim_win_get_cursor(0)
  local row = opts.range and opts.range[1] or cur[1]
  if doc.kind[row] ~= "body" or doc.quote_code[row] then
    return notify("anchors go in body text (not code, front matter or threads)", vim.log.levels.WARN)
  end
  with_label(opts, function(label)
    local ok, err = valid_label(label)
    if not ok then
      return notify(err, vim.log.levels.ERROR)
    end
    label = vim.trim(label)
    local existing = doc:find(label)
    local token = " [?" .. label .. "]"
    local anchor_row
    if opts.range then
      local srow, scol, erow, ecol = unpack(opts.range)
      local eline = doc.lines[erow]
      -- end of the last selected character (multi-byte safe; `$` selections
      -- report a huge column)
      local eend = #eline
      if ecol < #eline then
        eend = ecol + 1 + vim.str_utf_end(eline, ecol + 1)
      end
      api.nvim_buf_set_text(buf, erow - 1, eend, erow - 1, eend, { "==" .. token })
      api.nvim_buf_set_text(buf, srow - 1, scol, srow - 1, scol, { "==" })
      anchor_row = erow
    else
      local line = doc.lines[row]
      local col = cur[2] + 1
      local e = col
      if line:sub(col, col):find("%S") then
        e = (line:find("%s", col) or (#line + 1)) - 1
      else
        e = col - 1
      end
      api.nvim_buf_set_text(buf, row - 1, e, row - 1, e, { token })
      anchor_row = row
    end
    if existing then
      return notify("anchor added to existing thread [?" .. existing.label .. "]")
    end
    insert_thread(buf, R.document(buf), anchor_row, label)
  end)
end

return M
