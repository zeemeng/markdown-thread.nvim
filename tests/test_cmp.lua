local S = require("markdown-thread.cmp")
local api = vim.api

local function buffer(lines)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  return buf
end

return function(T)
  T.case("cmp: thread labels in body text", function()
    local buf = buffer({ "See [?wh", "", "> [?why ticks] Why?", "", "> [?Other] x", ">", "> +++" })
    local items = S.items(buf, "See [?wh", "")
    T.eq(vim.tbl_map(function(i) return i.label end, items), { "why ticks", "Other" })
    T.eq(items[1].insertText, "why ticks]")
    T.eq(items[1].detail, "open thread, line 3")
    T.eq(items[1].documentation, "Why?")
    T.eq(items[2].detail, "closed thread, line 5")
    T.eq(S.items(buf, "See [?wh", "] more")[1].insertText, "why ticks", "no second ]")
  end)

  T.case("cmp: headers offer anchors without threads", function()
    local buf = buffer({ "Text [?new one] and [?q] and [?NEW  one].", "", "> [?q] a", "", "> [?" })
    local items = S.items(buf, "> [?", "")
    T.eq(vim.tbl_map(function(i) return i.label end, items), { "new one" })
    T.eq(items[1].detail, "anchor without a thread")
  end)

  T.case("cmp: nothing outside label tokens", function()
    local buf = buffer({ "plain" })
    T.eq(S.items(buf, "plain", ""), {})
    T.eq(S.items(buf, "[?done] x", ""), {})
  end)

  T.case("cmp: source metadata", function()
    local s = S.new()
    T.eq(s:get_trigger_characters(), { "?" })
    local re = vim.regex("\\%(" .. s:get_keyword_pattern() .. "\\)\\m$")
    T.eq({ re:match_str("see [?why ti") }, { 6, 12 }, "keyword starts after [?")
  end)
end
