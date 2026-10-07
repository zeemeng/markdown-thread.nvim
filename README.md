# markdown-thread.nvim

Neovim support for [Markdown Thread](../markdown-thread/SPEC.md) (spec v0.1):
discussion threads inside Markdown documents.

```markdown
The dispatcher ==polls every five seconds== [?why ticks].

> [?why ticks] Why poll instead of reacting to events?
>
> <-- agent/model-x @ 2026-10-06T19:57-04:00
> Polling keeps the dispatcher stateless across restarts.
```

- **Rendering** (with [render-markdown.nvim]): a badge with the label and
  state on each thread header, chips for `-->` / `<--` / `+++` lines, a tint
  on thread lines, and anchor badges coloured by the thread's state. As with
  render-markdown, the cursor line shows the raw text.
- **Writing**: create a thread from a selection or at a word, follow up,
  close; Enter on an empty `> ` line inside a thread keeps the thread going.
- **Navigation**: next/previous thread, a location list of threads.
- **Checks**: the parser's errors and warnings as diagnostics.
- **Completion** (with [nvim-cmp]): thread labels after `[?`.

The parser is a Lua port of markdown-thread's reference parser and passes the
same conformance fixtures. Requires Neovim 0.10+.

## Setup

lazy.nvim:

```lua
{
  "markdown-thread.nvim", -- or dir = "~/src/markdown-thread.nvim"
  ft = "markdown",
  opts = {
    author = nil, -- name written on your --> and +++ lines
    timestamp = false, -- false | "date" | "datetime"
    diagnostics = "save", -- false | "save" | "change"
    keymaps = {
      new = "<leader>mt", followup = "<leader>mf", close = "<leader>mc",
      list = "<leader>ml", next = "]t", prev = "[t",
    },
  },
}
```

All keymaps are off by default.

### Rendering

render-markdown has one custom handler per language, so markdown-thread
provides marks for yours instead of installing its own:

```lua
require("render-markdown").setup({
  custom_handlers = {
    markdown = {
      extends = true,
      parse = function(ctx)
        local marks = {}
        -- ... your own marks ...
        local ok, mdthread = pcall(require, "markdown-thread")
        if ok then
          vim.list_extend(marks, mdthread.marks(ctx))
        end
        return marks
      end,
    },
  },
})
```

### Enter inside threads

`require("markdown-thread").empty_quote_enter()` handles Enter on an empty
`> ` line of a thread: the line becomes a blank `>` line and a new `> ` line
follows; a second empty line ends the thread. It returns `false` when the
line is not in a thread, so call it from your own Enter handling first.

### Completion

Add the source to nvim-cmp: `{ name = "markdown_thread" }`. It answers only
in Markdown buffers.

## Commands

| Command | Does |
|---|---|
| `:MdThread list [state]` | location list of threads (`open`, `answered`, `closed`, `empty`, `duplicate`) |
| `:MdThread next [open]` / `prev [open]` | jump to the next/previous thread header |
| `:MdThread new` | point anchor after the word under the cursor + thread; with a visual range, `==selection== [?label]` |
| `:MdThread followup` | blank `>` line + `-->` at the end of the thread under the cursor |
| `:MdThread close [reason]` | `+++` line (name/time from `author` / `timestamp`) |
| `:MdThread check` | parser diagnostics now |

`:checkhealth markdown-thread` reports what is available.

## Highlights

`MdThreadLine` (thread tint, default `CursorLine`), `MdThreadLabel`,
`MdThreadOpen`, `MdThreadAnswered`, `MdThreadClosed`, `MdThreadEmpty`,
`MdThreadDuplicate`, `MdThreadOrphan`, `MdThreadAnnotator`,
`MdThreadResponder`, `MdThreadMeta`. All are `default` links, so a colour
scheme or `nvim_set_hl` can override them.

## Tests

```sh
make test   # needs the markdown-thread spec repo next to this one,
            # or MDTHREAD_FIXTURES=/path/to/markdown-thread/fixtures
```

## License

MIT

[render-markdown.nvim]: https://github.com/MeanderingProgrammer/render-markdown.nvim
[nvim-cmp]: https://github.com/hrsh7th/nvim-cmp
