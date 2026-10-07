-- nvim-cmp source "markdown_thread": thread labels after `[?`.
-- In body text it offers existing threads; at the start of a quote line
-- (`> [?`) it offers anchor labels that have no thread yet.
local P = require("markdown-thread.parser")
local R = require("markdown-thread.render")

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  return vim.bo.filetype == "markdown"
end

function source:get_debug_name()
  return "markdown_thread"
end

function source:get_trigger_characters()
  return { "?" }
end

-- the label typed so far: everything after "[?" up to the cursor
function source:get_keyword_pattern()
  return [[\%(\[?\)\@<=[^\]\[]*]]
end

--- Completion items for a line prefix (exposed for tests).
function source.items(buf, before, after)
  if not before:match("%[%?[^%[%]]*$") then
    return {}
  end
  local doc = R.document(buf)
  local close = (after or ""):sub(1, 1) == "]" and "" or "]"
  local header = before:match("^%s*>%s?%[%?[^%[%]]*$") ~= nil
  local items, seen = {}, {}
  local kind = 18 -- CompletionItemKind.Reference
  if header then
    local threads = {}
    for _, t in ipairs(doc.threads) do
      threads[t.key] = true
    end
    for _, o in ipairs(doc.orphans) do
      if not threads[o.key] and not seen[o.key] then
        seen[o.key] = true
        items[#items + 1] = {
          label = o.label,
          filterText = o.label,
          insertText = o.label .. close,
          kind = kind,
          detail = "anchor without a thread",
        }
      end
    end
    return items
  end
  for _, t in ipairs(doc.threads) do
    if not t.duplicate and not seen[t.key] then
      seen[t.key] = true
      local opener = t.messages[1] and t.messages[1].kind == "opener" and table.concat(t.messages[1].body, "\n")
      items[#items + 1] = {
        label = t.label,
        filterText = t.label,
        insertText = t.label .. close,
        kind = kind,
        detail = P.state(t) .. " thread, line " .. t.start,
        documentation = opener or nil,
      }
    end
  end
  return items
end

function source:complete(params, callback)
  local ctx = params.context
  local line = ctx.cursor_line
  local col = ctx.cursor.col -- 1-based byte column of the cursor
  local before = line:sub(1, col - 1)
  local after = line:sub(col)
  callback({ items = source.items(ctx.bufnr, before, after), isIncomplete = false })
end

return source
