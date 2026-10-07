local R = require("markdown-thread.render")
local C = require("markdown-thread.config")

local function buffer(text)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  return buf
end

local function find(marks, pred)
  local out = {}
  for _, m in ipairs(marks) do
    if pred(m) then
      out[#out + 1] = m
    end
  end
  return out
end

local function virt(marks, row)
  return find(marks, function(m)
    return m.start_row == row and m.opts.virt_text ~= nil
  end)
end

return function(T)
  C.set({})

  T.case("render: basic fixture marks", function()
    local buf = buffer(T.read(T.fixtures .. "/parse/basic.md"))
    local marks = R.marks({ buf = buf })
    -- header badge and concealed token
    local h = virt(marks, 2)
    T.eq(#h, 1, "one header badge")
    T.eq(h[1].start_col, 2)
    T.eq(h[1].opts.virt_text, { { "󰍩 why ticks", "MdThreadLabel" }, { " · closed", "MdThreadClosed" } })
    local hc = find(marks, function(m) return m.start_row == 2 and m.opts.conceal == "" end)
    T.eq({ hc[1].start_col, hc[1].opts.end_col, hc[1].conceal }, { 2, 14, true }, "header conceal")
    -- chips
    T.eq(virt(marks, 4)[1].opts.virt_text,
      { { "󰚩 agent/model-x", "MdThreadResponder" }, { "  2026-10-06 19:57", "MdThreadMeta" } })
    T.eq(virt(marks, 7)[1].opts.virt_text,
      { { "󰀄 Alice", "MdThreadAnnotator" }, { "  2026-10-06 20:03", "MdThreadMeta" } })
    T.eq(virt(marks, 13)[1].opts.virt_text, {
      { "󰄬 closed", "MdThreadClosed" }, { " · Alice", "MdThreadMeta" },
      { " · 2026-10-06", "MdThreadMeta" }, { " · keep five seconds for now", "MdThreadMeta" },
    })
    local mc = find(marks, function(m) return m.start_row == 13 and m.opts.conceal == "" end)[1]
    T.eq({ mc.start_col, mc.opts.end_col }, { 2, #"> +++ Alice @ 2026-10-06 ! keep five seconds for now" })
    -- anchor badge, coloured by state
    T.eq(virt(marks, 0)[1].opts.virt_text, { { "󰍩 why ticks", "MdThreadClosed" } })
    T.eq(virt(marks, 0)[1].start_col, 44)
    -- tint on every thread line, never concealed
    local tint = find(marks, function(m) return m.opts.line_hl_group == "MdThreadLine" end)
    T.eq(#tint, 12)
    T.ok(tint[1].conceal == false)
  end)

  T.case("render: every mark is a valid extmark", function()
    local ns = vim.api.nvim_create_namespace("mdthread-test")
    for _, f in ipairs(T.glob("parse/*.md")) do
      local buf = buffer(T.read(f))
      for _, m in ipairs(R.marks({ buf = buf })) do
        local o = vim.deepcopy(m.opts)
        o.strict = true
        local ok, err = pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.start_row, m.start_col, o)
        T.ok(ok, vim.fn.fnamemodify(f, ":t") .. ": " .. tostring(err))
      end
    end
  end)

  T.case("render: orphan, duplicate, open, empty", function()
    local buf = buffer(table.concat({
      "See [?gone] and [?dup] and [?q].",
      "",
      "> [?dup] a",
      "",
      "> [?DUP] b",
      "",
      "> [?q] open question",
      "",
      "> [?e]",
    }, "\n"))
    local marks = R.marks({ buf = buf })
    local row0 = virt(marks, 0)
    local texts = {}
    for _, m in ipairs(row0) do
      texts[#texts + 1] = m.opts.virt_text[1]
    end
    T.eq(texts, { { "󰍩 q", "MdThreadOpen" }, { "󰍩 gone?", "MdThreadOrphan" } })
    T.eq(virt(marks, 2)[1].opts.virt_text[2], { " · duplicate", "MdThreadDuplicate" })
    T.eq(virt(marks, 8)[1].opts.virt_text[2], { " · empty", "MdThreadEmpty" })
  end)

  T.case("render: injected trees and disabled rendering return nothing", function()
    local buf = buffer("> [?q] a")
    T.eq(R.marks({ buf = buf, root = { range = function() return 5, 0, 9, 0 end } }), {})
    T.ok(#R.marks({ buf = buf, root = { range = function() return 0, 0, 1, 0 end } }) > 0)
    C.set({ render = { enabled = false } })
    T.eq(R.marks({ buf = buf }), {})
    C.set({ render = { tint = false } })
    T.eq(#find(R.marks({ buf = buf }), function(m) return m.opts.line_hl_group end), 0)
    C.set({})
  end)

  T.case("render: document cache follows changedtick", function()
    local buf = buffer("> [?q] a")
    local d1 = R.document(buf)
    T.ok(R.document(buf) == d1, "cached")
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, { "> [?r] b" })
    T.eq(R.document(buf).threads[1].label, "r")
  end)

  T.case("render: short_time", function()
    T.eq(R.short_time("2026-10-06T19:57-04:00"), "2026-10-06 19:57")
    T.eq(R.short_time("2026-10-06"), "2026-10-06")
  end)
end
