-- Options. setup() merges user options into M.options.
local M = {}

M.defaults = {
  -- Name written on your `-->` and `+++` lines (nil: no name).
  author = nil,
  -- Time on your `-->` and `+++` lines: false, "date" or "datetime".
  timestamp = false,
  render = {
    enabled = true, -- marks for render-markdown (see README)
    tint = true, -- background on thread lines
  },
  icons = {
    thread = "󰍩 ",
    anchor = "󰍩 ",
    annotator = "󰀄 ",
    responder = "󰚩 ",
    closed = "󰄬 ",
  },
  -- Text shown for a `-->`/opener without a name.
  annotator_label = "you",
  -- Diagnostics from the parser: false, "save" (on write) or "change".
  diagnostics = "save",
  -- Buffer-local keys in Markdown buffers; false disables one.
  keymaps = {
    new = false, -- n: point anchor at cursor; x: anchor the selection
    followup = false,
    close = false,
    next = false,
    prev = false,
    list = false,
  },
  -- nvim-cmp source "markdown_thread" (labels after `[?`).
  cmp = true,
}

M.options = vim.deepcopy(M.defaults)

function M.set(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

M.highlights = {
  MdThreadLine = { link = "CursorLine" },
  MdThreadLabel = { link = "Special" },
  MdThreadOpen = { link = "DiagnosticWarn" },
  MdThreadAnswered = { link = "DiagnosticInfo" },
  MdThreadClosed = { link = "DiagnosticOk" },
  MdThreadEmpty = { link = "Comment" },
  MdThreadDuplicate = { link = "DiagnosticError" },
  MdThreadOrphan = { link = "Comment" },
  MdThreadAnnotator = { link = "Identifier" },
  MdThreadResponder = { link = "Function" },
  MdThreadMeta = { link = "Comment" },
}

function M.define_highlights()
  for name, spec in pairs(M.highlights) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", spec, { default = true }))
  end
end

M.state_hl = {
  open = "MdThreadOpen",
  answered = "MdThreadAnswered",
  closed = "MdThreadClosed",
  empty = "MdThreadEmpty",
  duplicate = "MdThreadDuplicate",
}

return M
