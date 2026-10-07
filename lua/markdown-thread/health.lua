local M = {}

function M.check()
  local h = vim.health
  h.start("markdown-thread")
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim 0.10 or newer is required")
  end
  local ok_rm = pcall(require, "render-markdown")
  if ok_rm then
    h.ok("render-markdown.nvim found; add markdown-thread's marks to its custom handler (:help markdown-thread-render)")
  else
    h.warn("render-markdown.nvim not found: threads are not rendered (editing commands still work)")
  end
  local ok_cmp = pcall(require, "cmp")
  if ok_cmp then
    h.ok("nvim-cmp found; source name: markdown_thread")
  else
    h.info("nvim-cmp not found: no label completion")
  end
  local opts = require("markdown-thread.config").options
  h.info(("author=%s timestamp=%s diagnostics=%s"):format(
    tostring(opts.author), tostring(opts.timestamp), tostring(opts.diagnostics)))
end

return M
