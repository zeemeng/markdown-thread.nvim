local E = require("markdown-thread.edit")
local C = require("markdown-thread.config")
local api = vim.api

local function setbuf(lines, cursor)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  if cursor then
    api.nvim_win_set_cursor(0, cursor)
  end
  return buf
end

local function lines(buf)
  return api.nvim_buf_get_lines(buf or 0, 0, -1, true)
end

local function file_lines(text)
  local l = vim.split(text, "\n", { plain = true })
  if l[#l] == "" then
    table.remove(l)
  end
  return l
end

local function quiet(fn)
  local orig = vim.notify
  local msgs = {}
  vim.notify = function(m)
    msgs[#msgs + 1] = m
  end
  local ok, err = pcall(fn)
  vim.notify = orig
  assert(ok, err)
  return msgs
end

return function(T)
  C.set({})

  for _, name in ipairs({ "close-fields", "close-bare" }) do
    T.case("edit: close matches ops fixture " .. name, function()
      local op = vim.json.decode(T.read(T.fixtures .. "/ops/" .. name .. ".op.json"))
      setbuf(file_lines(T.read(T.fixtures .. "/ops/" .. name .. ".md")), { 1, 0 })
      E.close(op.reason, { name = op.name or false, timestamp = op.timestamp or false })
      T.eq(lines(), file_lines(T.read(T.fixtures .. "/ops/" .. name .. ".out.md")))
    end)
  end

  T.case("edit: close refuses closed threads and non-threads", function()
    setbuf({ "> [?q] a", ">", "> +++" }, { 1, 0 })
    local msgs = quiet(function() E.close() end)
    T.ok(msgs[1]:find("already closed"), msgs[1])
    setbuf({ "text" }, { 1, 0 })
    msgs = quiet(function() E.close() end)
    T.ok(msgs[1]:find("not in a thread"), msgs[1])
  end)

  T.case("edit: close uses configured author and date", function()
    C.set({ author = "Alice", timestamp = "date" })
    setbuf({ "> [?q] a" }, { 1, 0 })
    E.close("done")
    T.eq(lines()[2], ">")
    T.ok(lines()[3]:match("^> %+%+%+ Alice @ %d%d%d%d%-%d%d%-%d%d ! done$"), lines()[3])
    C.set({})
  end)

  T.case("edit: followup", function()
    setbuf({ "> [?q] Why?", ">", "> <-- bot @ 2026-10-06T10:00Z", "> Because.", "", "after" }, { 1, 0 })
    E.followup()
    vim.cmd("stopinsert")
    T.eq(lines(), { "> [?q] Why?", ">", "> <-- bot @ 2026-10-06T10:00Z", "> Because.", ">", "> -->", "> ", "", "after" })
    T.eq(api.nvim_win_get_cursor(0)[1], 7)
    -- a thread that already ends with a blank `>` line gets no second one
    setbuf({ "> [?q] Why?", ">" }, { 1, 0 })
    E.followup()
    vim.cmd("stopinsert")
    T.eq(lines(), { "> [?q] Why?", ">", "> -->", "> " })
    C.set({ author = "Alice", timestamp = "datetime" })
    setbuf({ "  > [?q] Why?" }, { 1, 0 })
    E.followup()
    vim.cmd("stopinsert")
    T.ok(lines()[3]:match("^  > %-%-> Alice @ %d%d%d%d%-%d%d%-%d%dT%d%d:%d%d[+-]%d%d:%d%d$"), lines()[3])
    T.eq(lines()[4], "  > ")
    C.set({})
  end)

  T.case("edit: Enter on empty quote lines in a thread", function()
    setbuf({ "> [?q] a", "> " }, { 2, 2 })
    T.ok(E.empty_quote_enter())
    T.eq(lines(), { "> [?q] a", ">", "> " })
    -- row only: normal mode clamps the column (insert mode is covered by the
    -- integration test)
    T.eq(api.nvim_win_get_cursor(0)[1], 3)
    T.ok(E.empty_quote_enter(), "second Enter ends the thread")
    T.eq(lines(), { "> [?q] a", "", "" })
    T.eq(api.nvim_win_get_cursor(0), { 3, 0 })
    -- indented thread in a list
    setbuf({ "- item [?q].", "", "  > [?q] a", "  > " }, { 4, 4 })
    T.ok(E.empty_quote_enter())
    T.eq(lines(), { "- item [?q].", "", "  > [?q] a", "  >", "  > " })
    -- ordinary quote, non-empty line, header line: not handled
    setbuf({ "> plain", "> " }, { 2, 2 })
    T.ok(not E.empty_quote_enter())
    setbuf({ "> [?q] a", "> text" }, { 2, 3 })
    T.ok(not E.empty_quote_enter())
    setbuf({ "> [?q]" }, { 1, 2 })
    T.ok(not E.empty_quote_enter())
    T.eq(lines(), { "> [?q]" })
  end)

  T.case("edit: new range anchor and thread", function()
    setbuf({ "The dispatcher polls every five seconds.", "Then it sleeps.", "", "Next." }, { 1, 0 })
    E.new({ range = { 1, 15, 1, 38 }, label = "ticks" })
    vim.cmd("stopinsert")
    T.eq(lines(), {
      "The dispatcher ==polls every five seconds== [?ticks].",
      "Then it sleeps.",
      "",
      "> [?ticks] ",
      "",
      "Next.",
    })
    T.eq(api.nvim_win_get_cursor(0)[1], 4)
  end)

  T.case("edit: new handles multi-byte ends, $ selections, end of file", function()
    setbuf({ "café au lait" }, { 1, 0 })
    E.new({ range = { 1, 0, 1, 3 }, label = "c" })
    vim.cmd("stopinsert")
    T.eq(lines(), { "==café== [?c] au lait", "", "> [?c] " })
    setbuf({ "whole line" }, { 1, 0 })
    E.new({ range = { 1, 0, 1, 2147483646 }, label = "w" })
    vim.cmd("stopinsert")
    T.eq(lines()[1], "==whole line== [?w]")
  end)

  T.case("edit: new point anchor after the word", function()
    setbuf({ "The dispatcher polls often." }, { 1, 16 })
    E.new({ label = "p" })
    vim.cmd("stopinsert")
    T.eq(lines(), { "The dispatcher polls [?p] often.", "", "> [?p] " })
  end)

  T.case("edit: new thread placement in lists and quotes", function()
    setbuf({ "1. First item", "   continues here.", "2. Second item" }, { 1, 3 })
    E.new({ label = "x" })
    vim.cmd("stopinsert")
    T.eq(lines(), { "1. First [?x] item", "   continues here.", "", "   > [?x] ", "", "2. Second item" })
    setbuf({ "> quoted text", "> more", "", "after" }, { 1, 2 })
    E.new({ label = "y" })
    vim.cmd("stopinsert")
    T.eq(lines(), { "> quoted [?y] text", "> more", "", "> [?y] ", "", "after" })
  end)

  T.case("edit: new with an existing label only adds the anchor", function()
    setbuf({ "One here.", "", "> [?q] a", "", "Two here." }, { 5, 0 })
    local msgs = quiet(function() E.new({ label = "Q" }) end)
    T.eq(lines(), { "One here.", "", "> [?q] a", "", "Two [?Q] here." })
    T.ok(msgs[1]:find("existing thread"), msgs[1])
  end)

  T.case("edit: new refuses code, threads and bad labels", function()
    setbuf({ "```", "code", "```" }, { 2, 0 })
    quiet(function() E.new({ label = "x" }) end)
    T.eq(lines(), { "```", "code", "```" })
    setbuf({ "> [?q] a" }, { 1, 3 })
    quiet(function() E.new({ label = "x" }) end)
    T.eq(lines(), { "> [?q] a" })
    setbuf({ "text" }, { 1, 0 })
    local msgs = quiet(function() E.new({ label = "a]b" }) end)
    T.eq(lines(), { "text" })
    T.ok(msgs[1]:find("cannot contain"), msgs[1])
    msgs = quiet(function() E.new({ label = "  " }) end)
    T.ok(msgs[1]:find("empty"), msgs[1])
  end)

  T.case("edit: jump, items, check", function()
    local buf = setbuf(file_lines(T.read(T.fixtures .. "/parse/states.md")), { 1, 0 })
    E.jump(1)
    T.eq(api.nvim_win_get_cursor(0)[1], 3)
    E.jump(1, true)
    T.eq(api.nvim_win_get_cursor(0)[1], 17, "next open skips answered/closed")
    E.jump(-1)
    T.eq(api.nvim_win_get_cursor(0)[1], 10)
    local msgs = quiet(function() E.jump(-1, true); E.jump(-1, true) end)
    T.eq(api.nvim_win_get_cursor(0)[1], 3)
    T.ok(msgs[1]:find("no open thread above"), msgs[1])
    local items = E.items(buf, "open")
    T.eq(vim.tbl_map(function(i) return i.text end, items), { "[open] open: Question.", "[open] reopened: Question." })
    T.eq(#E.items(buf), 5)
    local d = E.check(buf)
    T.eq(#d, 1)
    T.eq(d[1].code, "empty-thread")
    setbuf(file_lines(T.read(T.fixtures .. "/parse/duplicates.md")))
    d = E.check(0)
    T.eq(d[1].severity, vim.diagnostic.severity.ERROR)
  end)
end
