-- markdown-thread.nvim: render, write and navigate Markdown Thread
-- discussions (markdown-thread SPEC.md v0.2).
local C = require("markdown-thread.config")

local M = {}

M.parser = require("markdown-thread.parser")
M.render = require("markdown-thread.render")
M.edit = require("markdown-thread.edit")

--- render-markdown custom-handler marks; call from your handler's parse().
function M.marks(ctx)
  return M.render.marks(ctx)
end

--- For an Enter mapping: handle Enter on an empty `> ` line in a thread.
M.empty_quote_enter = function()
  return M.edit.empty_quote_enter()
end

local subcommands = {
  list = function(args)
    M.edit.list(args[1])
  end,
  next = function(args)
    M.edit.jump(1, args[1] == "open")
  end,
  prev = function(args)
    M.edit.jump(-1, args[1] == "open")
  end,
  new = function(_, cmd)
    if cmd.range == 2 then
      local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
      M.edit.new({ range = { s[2], s[3] - 1, e[2], e[3] - 1 } })
    else
      M.edit.new({})
    end
  end,
  followup = function()
    M.edit.followup()
  end,
  close = function(args)
    M.edit.close(#args > 0 and table.concat(args, " ") or nil)
  end,
  check = function()
    local n = #M.edit.check(0)
    vim.notify(("markdown-thread: %d problem(s)"):format(n))
  end,
}

local function command(cmd)
  local args = vim.split(vim.trim(cmd.args), "%s+", { trimempty = true })
  local name = table.remove(args, 1) or "list"
  local fn = subcommands[name]
  if not fn then
    return vim.notify("markdown-thread: unknown subcommand " .. name, vim.log.levels.ERROR)
  end
  fn(args, cmd)
end

local function complete(arglead, line)
  local words = vim.split(line, "%s+", { trimempty = true })
  local n = #words + (line:match("%s$") and 1 or 0)
  if n <= 2 then
    return vim.tbl_filter(function(s)
      return s:find(arglead, 1, true) == 1
    end, vim.tbl_keys(subcommands))
  end
  if words[2] == "list" then
    return { "open", "answered", "closed", "empty", "duplicate", "all" }
  elseif words[2] == "next" or words[2] == "prev" then
    return { "open" }
  end
  return {}
end

local key_actions = {
  new = { { "n", function() M.edit.new({}) end },
    { "x", ":MdThread new<CR>" } },
  followup = { { "n", function() M.edit.followup() end } },
  close = { { "n", function() M.edit.close() end } },
  next = { { "n", function() M.edit.jump(1, false) end } },
  prev = { { "n", function() M.edit.jump(-1, false) end } },
  list = { { "n", function() M.edit.list() end } },
}

local descs = {
  new = "Thread: new anchor + thread",
  followup = "Thread: follow up",
  close = "Thread: close",
  next = "Thread: next",
  prev = "Thread: previous",
  list = "Thread: list",
}

function M.attach(buf)
  for action, lhs in pairs(C.options.keymaps) do
    if lhs and key_actions[action] then
      for _, m in ipairs(key_actions[action]) do
        vim.keymap.set(m[1], lhs, m[2], { buffer = buf, desc = descs[action], silent = true })
      end
    end
  end
  -- open thread lists (:MdThread list) follow the buffer
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
    group = vim.api.nvim_create_augroup("MarkdownThreadList" .. buf, {}),
    buffer = buf,
    callback = function()
      M.edit.refresh_lists(buf)
    end,
  })
  local diag = C.options.diagnostics
  if diag then
    local group = vim.api.nvim_create_augroup("MarkdownThreadDiag" .. buf, {})
    vim.api.nvim_create_autocmd(diag == "change" and { "TextChanged", "InsertLeave", "BufWritePost" } or { "BufWritePost" }, {
      group = group,
      buffer = buf,
      callback = function()
        M.edit.check(buf)
      end,
    })
  end
end

function M.setup(opts)
  C.set(opts)
  C.define_highlights()
  local group = vim.api.nvim_create_augroup("MarkdownThread", {})
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = C.define_highlights })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
    callback = function(ev)
      M.attach(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      M.render.forget(ev.buf)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "markdown" then
      M.attach(buf)
    end
  end
  vim.api.nvim_create_user_command("MdThread", command, {
    nargs = "*",
    range = true,
    complete = complete,
    desc = "Markdown threads: list, next, prev, new, followup, close, check",
  })
  if C.options.cmp then
    local ok, cmp = pcall(require, "cmp")
    if ok then
      cmp.register_source("markdown_thread", require("markdown-thread.cmp").new())
    end
  end
end

return M
