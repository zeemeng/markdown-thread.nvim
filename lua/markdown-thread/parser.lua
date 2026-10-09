-- Markdown Thread spec v0.2 parser (port of markdown-thread's reference
-- parser, skill/markdown-thread/scripts/mdthread.py). Produces the same model
-- and diagnostics; tests compare both against markdown-thread's fixtures.
--
-- Positions: rows are 0-based internally; to_json() emits 1-based lines and
-- 0-based byte columns like the fixtures. Differences from the Python parser:
-- label keys use vim.fn.tolower (simple Unicode lowercasing, no full case
-- folding such as "ß" -> "ss", no NFC normalisation); "whitespace" is ASCII.

local M = {}

M.SPEC_VERSION = "0.2"

---------------------------------------------------------------------------
-- small helpers

local function is_blank(s)
  return s:find("^%s*$") ~= nil
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function is_space(ch)
  return ch ~= nil and ch ~= "" and ch:find("^%s$") ~= nil
end

--- §4.1 label key: collapse whitespace, trim, lowercase.
function M.label_key(label)
  local s = trim((label:gsub("%s+", " ")))
  if vim and vim.fn and vim.fn.tolower then
    return vim.fn.tolower(s)
  end
  return s:lower()
end

--- §3.1 quote line: returns the byte index where content starts (1-based)
--- and the leading whitespace, or nil.
local function quote_match(line)
  local ws = line:match("^([ \t]*)>")
  if not ws then
    return nil
  end
  local e = #ws + 2 -- first byte after ">"
  local c = line:sub(e, e)
  if c == " " or c == "\t" then
    e = e + 1
  end
  return e, ws
end

--- §3.3.2 opening fence on `content`: returns char, length or nil.
local function fence_open(content)
  local run = content:match("^[ \t]*(```+)") or content:match("^[ \t]*(~~~+)")
  if not run then
    return nil
  end
  if run:sub(1, 1) == "`" then
    local rest = content:sub(#content:match("^[ \t]*") + #run + 1)
    if rest:find("`", 1, true) then
      return nil
    end
  end
  return run:sub(1, 1), #run
end

local function fence_closes(content, ch, len)
  local run = content:match("^[ \t]*(" .. (ch == "`" and "`" or "~") .. "+)[ \t]*$")
  return run ~= nil and #run >= len
end

--- Replace code spans (maximal backtick runs, matching lengths, one line)
--- with spaces of the same byte length.
local function mask_code_spans(s)
  local out, i, n = {}, 1, #s
  local last = 1
  while i <= n do
    local a, b = s:find("`+", i)
    if not a then
      break
    end
    local len = b - a + 1
    -- find the next maximal run of exactly `len` backticks after b, with
    -- at least one character of content in between
    local j = b + 1
    local close_a, close_b
    while true do
      local c1, c2 = s:find("`+", j)
      if not c1 then
        break
      end
      if c2 - c1 + 1 == len and c1 > b + 1 then
        close_a, close_b = c1, c2
        break
      end
      j = c2 + 1
    end
    if close_a then
      out[#out + 1] = s:sub(last, a - 1)
      out[#out + 1] = string.rep(" ", close_b - a + 1)
      last = close_b + 1
      i = close_b + 1
    else
      i = b + 1
    end
  end
  out[#out + 1] = s:sub(last)
  return table.concat(out)
end

--- Strip leading whitespace and block-quote markers (QUOTE_PREFIX_RE /
--- the prefix of BLOCK_START_RE). Returns the remainder.
local function strip_quote_prefix(line)
  local s = line:gsub("^[ \t]*", "")
  while s:sub(1, 1) == ">" do
    s = s:sub(2)
    local c = s:sub(1, 1)
    if c == " " or c == "\t" then
      s = s:sub(2)
    end
  end
  return (s:gsub("^[ \t]*", ""))
end

--- Length of the leading `[ \t]*(?:>[ \t]?)+` prefix, 0 if none.
local function quote_prefix_len(line)
  local i = #line:match("^[ \t]*") + 1
  if line:sub(i, i) ~= ">" then
    return 0
  end
  while line:sub(i, i) == ">" do
    i = i + 1
    local c = line:sub(i, i)
    if c == " " or c == "\t" then
      i = i + 1
    end
  end
  return i - 1
end

local function thematic(rest, ch)
  local count = 0
  for c in rest:gmatch(".") do
    if c == ch then
      count = count + 1
    elseif c ~= " " and c ~= "\t" then
      return false
    end
  end
  return count >= 3
end

--- §7.1 block start: heading, list item or thematic break.
local function block_start(line)
  local r = strip_quote_prefix(line)
  if r:sub(1, 1) == "#" then
    return true
  end
  if r:find("^[-*+][ \t]") or r:find("^%d+[.)][ \t]") then
    return true
  end
  return thematic(r, "*") or thematic(r, "-") or thematic(r, "_")
end

local function is_heading(line)
  return strip_quote_prefix(line):sub(1, 1) == "#"
end

--- §5.3 longest timestamp prefix of s, or nil.
local function timestamp_prefix(s)
  local d = s:match("^%d%d%d%d%-%d%d%-%d%d")
  if not d then
    return nil
  end
  local pos = #d + 1
  local t = s:match("^T%d%d:%d%d", pos)
  if t then
    pos = pos + #t
    local sec = s:match("^:%d%d", pos)
    if sec then
      pos = pos + #sec
    end
    local off = s:match("^Z", pos) or s:match("^[+-]%d%d:%d%d", pos)
    if off then
      pos = pos + #off
    end
  end
  return s:sub(1, pos - 1)
end
M.timestamp_prefix = timestamp_prefix

function M.is_full_timestamp(s)
  return s:find("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d") ~= nil
    and timestamp_prefix(s) == s
    and (s:find("Z$") ~= nil or s:find("[+-]%d%d:%d%d$") ~= nil)
end

--- First delimiter `ch` at start or after whitespace, followed by whitespace,
--- end, or (when allow_digit) a digit. Returns its byte index or nil.
local function find_delim(text, ch, allow_digit)
  local i = 1
  while true do
    local p = text:find(ch, i, true)
    if not p then
      return nil
    end
    local before = text:sub(p - 1, p - 1)
    local after = text:sub(p + 1, p + 1)
    local ok_before = p == 1 or is_space(before)
    local ok_after = after == "" or is_space(after) or (allow_digit and after:find("^%d") ~= nil)
    if ok_before and ok_after then
      return p
    end
    i = p + 1
  end
end

--- §5.2 marker fields. Returns name, timestamp, reason, ignored, bad_timestamp.
function M.parse_fields(marker, text)
  local reason
  if marker == "+++" then
    local r = find_delim(text, "!", false)
    if r then
      local rs = trim(text:sub(r + 1))
      reason = rs ~= "" and rs or nil
      text = text:sub(1, r - 1)
    end
  end
  local a = find_delim(text, "@", true)
  if not a then
    local n = trim(text)
    return n ~= "" and n or nil, nil, reason, nil, nil
  end
  local name = trim(text:sub(1, a - 1))
  name = name ~= "" and name or nil
  local rest = text:sub(a + 1):gsub("^%s+", "")
  local ts = timestamp_prefix(rest)
  if not ts then
    local bad = trim(rest)
    return name, nil, reason, nil, bad ~= "" and bad or nil
  end
  local ignored = trim(rest:sub(#ts + 1))
  return name, ts, reason, ignored ~= "" and ignored or nil, nil
end

local function trim_blank(lines)
  local a, b = 1, #lines
  while a <= b and is_blank(lines[a]) do
    a = a + 1
  end
  while b >= a and is_blank(lines[b]) do
    b = b - 1
  end
  local out = {}
  for i = a, b do
    out[#out + 1] = lines[i]
  end
  return out
end

--- Label token at the start of s: returns label, end index (inclusive).
local function label_token_at_start(s)
  local label = s:match("^%[%?([^%[%]]+)%]")
  if not label then
    return nil
  end
  return label, #label + 3
end

---------------------------------------------------------------------------
-- Document

local Document = {}
Document.__index = Document

function M.parse(text)
  if type(text) == "table" then
    text = table.concat(text, "\n")
  end
  local self = setmetatable({}, Document)
  self.text = text
  self.raw = vim.split(text, "\n", { plain = true })
  self.lines = {}
  for i, l in ipairs(self.raw) do
    self.lines[i] = l:sub(-1) == "\r" and l:sub(1, -2) or l
  end
  self.n = #self.lines
  self.offsets = {}
  local pos = 0
  for i, l in ipairs(self.raw) do
    self.offsets[i] = pos
    pos = pos + #l + 1
  end
  self.kind = {}
  self.masked = {}
  for i = 1, self.n do
    self.kind[i] = "body"
    self.masked[i] = self.lines[i]
  end
  self.threads = {}
  self.diagnostics = {}
  self.front_matter = { present = false, format = nil, autoremove_closed = false }
  self.linkdefs = {} -- key -> first row (1-based), insertion order in linkdef_order
  self.linkdef_order = {}
  self.comment_start = {}
  self.quote_code = {}
  self.orphans = {} -- label tokens in the body that match no thread
  self:_parse()
  return self
end

-- rows are 1-based Lua indexes in this file; diag takes 1-based rows
function Document:diag(severity, code, row, message)
  self.diagnostics[#self.diagnostics + 1] =
    { severity = severity, code = code, line = row, message = message, seq = #self.diagnostics }
end

function Document:errors()
  local out = {}
  for _, d in ipairs(self.diagnostics) do
    if d.severity == "error" then
      out[#out + 1] = d
    end
  end
  return out
end

--- Absolute 0-based byte offset -> { line (1-based), column (0-based) }.
function Document:pos(offset)
  local lo, hi = 1, self.n
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if self.offsets[mid] <= offset then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return { lo, offset - self.offsets[lo] }
end

function Document:_parse()
  local start = self:_front_matter()
  self:_regions(start)
  self:_threads()
  self:_duplicates()
  self:_anchors()
  table.sort(self.diagnostics, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    end
    local ae, be = a.severity == "error", b.severity == "error"
    if ae ~= be then
      return ae
    end
    if a.code ~= b.code then
      return a.code < b.code
    end
    return a.seq < b.seq
  end)
end

function Document:_front_matter()
  local first = self.lines[1]
  if self.n == 0 or (first ~= "---" and first ~= "+++") then
    return 1
  end
  local closers = first == "---" and { ["---"] = true, ["..."] = true } or { ["+++"] = true }
  for i = 2, self.n do
    if closers[self.lines[i]] then
      for j = 1, i do
        self.kind[j] = "front_matter"
      end
      self.front_matter.present = true
      self.front_matter.format = first == "---" and "yaml" or "toml"
      if first == "---" then
        local fm = {}
        for k = 2, i - 1 do
          fm[#fm + 1] = self.lines[k]
        end
        self:_front_matter_option(fm)
      end
      return i + 1
    end
  end
  return 1
end

local TRUE_WORDS = { ["true"] = true, ["True"] = true, ["TRUE"] = true }

local function fm_key(s, anchored)
  local pat = "autoremove_closed%s*:%s*([A-Za-z]+)"
  return s:match((anchored and "^" or "") .. pat)
end

function Document:_front_matter_option(fm)
  for k, line in ipairs(fm) do
    local inner = line:match("^threads:%s*{(.*)}%s*$") or line:match("^threads:%s*{(.*)}%s*#.*$")
    if inner then
      local v = fm_key(inner, false)
      self.front_matter.autoremove_closed = v ~= nil and TRUE_WORDS[v] == true
      return
    end
    if line:find("^threads:%s*$") or line:find("^threads:%s*#") then
      for j = k + 1, #fm do
        local sub = fm[j]
        if sub ~= "" and not sub:sub(1, 1):find("%s") then
          break
        end
        local v = fm_key(trim(sub), true)
        if v then
          self.front_matter.autoremove_closed = TRUE_WORDS[v] == true
          return
        end
      end
      return
    end
  end
end

function Document:_regions(start)
  local fence = nil -- { ch, len, in_quote }
  local in_comment = false
  for i = start, self.n do
    local line = self.lines[i]
    local qe = quote_match(line)
    local skip = false
    if fence then
      local ch, len, in_quote = fence[1], fence[2], fence[3]
      if in_quote and not qe then
        fence = nil -- block quote ended: fence ends with it
      else
        local content = (in_quote and qe) and line:sub(qe) or line
        if fence_closes(content, ch, len) then
          fence = nil
        end
        if in_quote then
          self.quote_code[i] = true
        else
          self.kind[i] = "code"
        end
        skip = true
      end
    end
    if not skip and in_comment then
      local e = line:find("-->", 1, true)
      if not e then
        self.masked[i] = string.rep(" ", #line)
        self.kind[i] = "comment"
        skip = true
      else
        self.masked[i] = string.rep(" ", e + 2) .. line:sub(e + 3)
        in_comment = false
        if is_blank(line:sub(e + 3)) then
          self.kind[i] = "comment"
          skip = true
        else
          self.comment_start[i] = true
        end
      end
    end
    if not skip then
      local content = qe and line:sub(qe) or line
      local ch, len = fence_open(content)
      if ch then
        fence = { ch, len, qe ~= nil }
        if qe then
          self.quote_code[i] = true
        else
          self.kind[i] = "code"
        end
      else
        local masked = mask_code_spans(self.masked[i])
        local out, j = {}, 1
        while true do
          local s = masked:find("<!--", j, true)
          if not s then
            out[#out + 1] = masked:sub(j)
            break
          end
          local e = masked:find("-->", s + 4, true)
          out[#out + 1] = masked:sub(j, s - 1)
          if not e then
            out[#out + 1] = string.rep(" ", #masked - s + 1)
            in_comment = true
            break
          end
          out[#out + 1] = string.rep(" ", e + 3 - s)
          j = e + 3
        end
        self.masked[i] = table.concat(out)
      end
    end
  end
end

function Document:_threads()
  local i = 1
  while i <= self.n do
    if self.kind[i] ~= "body" or self.comment_start[i] or not quote_match(self.lines[i]) then
      i = i + 1
    else
      local j = i
      while j + 1 <= self.n and self.kind[j + 1] == "body" and quote_match(self.lines[j + 1]) do
        j = j + 1
      end
      self:_quote(i, j)
      i = j + 1
    end
  end
end

local function header_label(first)
  local label, e = label_token_at_start(first)
  if not label or M.label_key(label) == "" then
    return nil
  end
  local after = first:sub(e + 1, e + 1)
  if after ~= "" and after ~= " " and after ~= "\t" then
    return nil
  end
  return label, e
end

function Document:_quote(s, e)
  local qe, indent = quote_match(self.lines[s])
  local first = self.lines[s]:sub(qe)
  local label, tok_end = header_label(first)
  if not label then
    local iq = quote_match(first)
    if iq then
      local il = label_token_at_start(first:sub(iq))
      if il and M.label_key(il) ~= "" then
        self:diag("warning", "nested-thread", s, "threads nested in block quotes are not supported in v0.2")
      end
    end
    return
  end
  local gt = self.lines[s]:find(">", 1, true)
  local t = {
    label = label,
    key = M.label_key(label),
    start = s,
    ["end"] = e,
    prefix = self.lines[s]:sub(1, gt),
    header_col = qe - 1, -- 0-based byte column of the label token
    header_end = qe - 1 + tok_end, -- exclusive
    messages = {},
    anchors = {},
    duplicate = false,
    content_col = {},
  }
  for k = s, e do
    self.kind[k] = "thread"
  end
  local content = {}
  for k = s, e do
    local ke, kws = quote_match(self.lines[k])
    content[#content + 1] = self.lines[k]:sub(ke)
    t.content_col[k] = ke - 1
    if kws ~= indent then
      self:diag("warning", "inconsistent-indent", k, "thread line indented differently from the header")
    end
  end
  -- markers (§5.1), skipping fenced code inside messages
  local markers = {}
  local fence = nil
  for k = 2, #content do
    local c = content[k]
    local handled = false
    if fence then
      if fence_closes(c, fence[1], fence[2]) then
        fence = nil
      end
      handled = true
    end
    if not handled then
      local ch, len = fence_open(c)
      if ch then
        fence = { ch, len, s + k - 1 }
        handled = true
      end
    end
    if not handled then
      local m = c:sub(1, 3)
      local nxt = c:sub(4, 4)
      if (m == "-->" or m == "<--" or m == "+++") and (nxt == "" or nxt == " " or nxt == "\t") then
        local after_blank = k == 2 or is_blank(content[k - 1])
        if m == "+++" and not after_blank then
          self:diag("warning", "close-without-blank", s + k - 1,
            "`+++` after a non-blank line is message text; add a blank `>` line before it to close")
        else
          if not after_blank then
            self:diag("warning", "missing-blank-before-marker", s + k - 1,
              "renderers merge this marker into the previous paragraph")
          end
          markers[#markers + 1] = { k = k, marker = m, rest = c:sub(4) }
        end
        handled = true
      end
    end
    if not handled then
      local hl = header_label(c)
      if hl then
        self:diag("warning", "header-in-thread", s + k - 1,
          "a header inside a thread is message text; separate threads with a blank line")
      end
    end
  end
  if fence then
    self:diag("warning", "unclosed-fence", fence[3], "code fence in a thread is never closed")
  end
  -- opener (§5.4)
  local first_marker = markers[1] and markers[1].k or #content + 1
  local opener = { trim(first:sub(tok_end + 1)) }
  for k = 2, first_marker - 1 do
    opener[#opener + 1] = content[k]
  end
  opener = trim_blank(opener)
  if #opener > 0 then
    t.messages[#t.messages + 1] = { kind = "opener", row = s, body = opener }
  end
  for idx, mk in ipairs(markers) do
    local nxt = markers[idx + 1] and markers[idx + 1].k or #content + 1
    local body = {}
    for k = mk.k + 1, nxt - 1 do
      body[#body + 1] = content[k]
    end
    local row = s + mk.k - 1
    local name, ts, reason, ignored, bad = M.parse_fields(mk.marker, mk.rest)
    if ignored then
      self:diag("warning", "marker-ignored-text", row, ("ignored after the timestamp: %q"):format(ignored))
    end
    if bad then
      self:diag("warning", "invalid-timestamp", row,
        ("not a timestamp (YYYY-MM-DD[THH:MM[:SS][offset]]): %q"):format(bad))
    end
    if mk.marker == "+++" then
      t.messages[#t.messages + 1] = { kind = "close", row = row, name = name, timestamp = ts, reason = reason }
      for _, b in ipairs(body) do
        if not is_blank(b) then
          self:diag("warning", "text-after-close", row + 1, "lines after `+++` belong to no message")
          break
        end
      end
    else
      local kind = mk.marker == "-->" and "annotator" or "responder"
      body = trim_blank(body)
      t.messages[#t.messages + 1] = { kind = kind, row = row, name = name, timestamp = ts, body = body }
      if #body == 0 then
        self:diag("warning", "empty-message", row, "message has no body")
      end
      if kind == "responder" and (not name or not ts) then
        self:diag("warning", "responder-marker-incomplete", row,
          "`<--` should carry a responder name and a timestamp")
      end
    end
  end
  if #t.messages == 0 then
    self:diag("warning", "empty-thread", s, "thread has no messages")
  end
  if s > 1 and self.kind[s - 1] ~= "thread" and not is_blank(self.lines[s - 1]) then
    self:diag("warning", "no-blank-before-thread", s,
      "Pandoc merges a quote into the paragraph above; add a blank line")
  end
  if e + 1 <= self.n and not is_blank(self.lines[e + 1]) then
    self:diag("warning", "lazy-continuation", e + 1,
      "this line ends the thread; CommonMark renderers continue the quote")
  end
  self.threads[#self.threads + 1] = t
end

function M.state(t)
  local last = t.messages[#t.messages]
  if not last then
    return "empty"
  end
  return ({ opener = "open", annotator = "open", responder = "answered", close = "closed" })[last.kind]
end

function Document:_duplicates()
  local seen = {}
  for _, t in ipairs(self.threads) do
    local first = seen[t.key]
    if first then
      first.duplicate = true
      t.duplicate = true
      self:diag("error", "duplicate-label", t.start,
        ("label %q is already used by the thread at line %d"):format(t.label, first.start))
    else
      seen[t.key] = t
    end
  end
end

function Document:_blocks()
  local blocks, block = {}, {}
  for i = 1, self.n do
    if self.kind[i] ~= "body" or self.quote_code[i] or is_blank(self.lines[i]) then
      if #block > 0 then
        blocks[#blocks + 1] = block
      end
      block = {}
    else
      if #block > 0 and (block_start(self.lines[i]) or is_heading(self.lines[block[#block]])) then
        blocks[#blocks + 1] = block
        block = {}
      end
      block[#block + 1] = i
    end
  end
  if #block > 0 then
    blocks[#blocks + 1] = block
  end
  return blocks
end

--- §7.1 highlights in block text: list of { s, e, text } (1-based, e inclusive).
local function find_highlights(text)
  local out = {}
  local n = #text
  local i = 1
  while i <= n - 1 do
    local p = text:find("==", i, true)
    if not p then
      break
    end
    local c = p + 2
    local ok = false
    if c <= n and not is_space(text:sub(c, c)) and text:sub(c, c + 1) ~= "==" then
      local q = text:find("==", c + 1, true)
      if q and not is_space(text:sub(q - 1, q - 1)) then
        local content = text:sub(c, q - 1)
        out[#out + 1] = { p, q + 1, trim((content:gsub("%s+", " "))) }
        i = q + 2
        ok = true
      end
    end
    if not ok then
      i = p + 1
    end
  end
  return out
end

--- Label tokens `[?x]` in text: list of { s, e, label } (1-based, e inclusive).
local function find_tokens(text)
  local out = {}
  local i = 1
  while true do
    local p = text:find("[?", i, true)
    if not p then
      break
    end
    local q = p + 2
    local stop = text:find("[%[%]]", q)
    if stop and text:sub(stop, stop) == "]" and stop > q then
      out[#out + 1] = { p, stop, text:sub(q, stop - 1) }
      i = stop + 1
    else
      i = p + 1
    end
  end
  return out
end

function Document:_anchors()
  local by_key, dup_keys = {}, {}
  for _, t in ipairs(self.threads) do
    if t.duplicate then
      dup_keys[t.key] = true
    else
      by_key[t.key] = t
    end
  end
  for _, block in ipairs(self:_blocks()) do
    local base = self.offsets[block[1]]
    local parts = {}
    for _, i in ipairs(block) do
      local m = self.masked[i]
      local ql = quote_prefix_len(m)
      if ql > 0 then
        m = string.rep(" ", ql) .. m:sub(ql + 1)
      end
      parts[#parts + 1] = m .. self.raw[i]:sub(#self.lines[i] + 1) -- keep CR width
    end
    local text = table.concat(parts, "\n")
    local highlights = find_highlights(text)
    for _, tok in ipairs(find_tokens(text)) do
      local st, en, label = tok[1], tok[2], tok[3]
      local key = M.label_key(label)
      if key ~= "" then
        local prev = st > 1 and text:sub(st - 1, st - 1) or ""
        local nxt = text:sub(en + 1, en + 1)
        local line_start = st
        while line_start > 1 and text:sub(line_start - 1, line_start - 1) ~= "\n" do
          line_start = line_start - 1
        end
        local abs = base + st - 1 -- 0-based absolute offset of "["
        if is_blank(text:sub(line_start, st - 1)) and nxt == ":" then
          if self.linkdefs[key] == nil then
            self.linkdefs[key] = self:pos(abs)[1]
            self.linkdef_order[#self.linkdef_order + 1] = key
          end
        elseif prev == "!" or prev == "\\" or prev == "]" or nxt == "(" or nxt == "[" then -- luacheck: ignore
          -- image, escape, link: not an anchor
        elseif dup_keys[key] then -- luacheck: ignore
          -- duplicated label: not an anchor
        else
          local t = by_key[key]
          if not t then
            self.orphans[#self.orphans + 1] = { start = abs, ["end"] = base + en, label = label, key = key }
            self:diag("warning", "orphan-anchor", self:pos(abs)[1],
              ("[?%s] matches no thread; it is plain text"):format(label))
          else
            local anchor = { kind = "point", start = abs, ["end"] = base + en, label = label }
            for _, h in ipairs(highlights) do
              local hs, he = h[1], h[2] -- he inclusive
              local gap = text:sub(he + 1, st - 1)
              local _, nl = gap:gsub("\n", "")
              if he < st and is_blank(gap) and nl <= 1 then
                anchor.kind = "range"
                anchor.highlight = h[3]
                anchor.hl_start = base + hs - 1
                anchor.hl_end = base + he
                break
              end
            end
            t.anchors[#t.anchors + 1] = anchor
          end
        end
      end
    end
  end
  for _, key in ipairs(self.linkdef_order) do
    if by_key[key] or dup_keys[key] then
      self:diag("warning", "label-is-link", self.linkdefs[key],
        "a link definition uses this thread's label; renderers show its anchors as links")
    end
  end
end

---------------------------------------------------------------------------
-- output (fixture format)

local function null(v)
  if v == nil then
    return vim.NIL
  end
  return v
end

function Document:to_json()
  local threads = {}
  for _, t in ipairs(self.threads) do
    local messages = {}
    for _, m in ipairs(t.messages) do
      local d = { kind = m.kind, line = m.row, name = null(m.name), timestamp = null(m.timestamp) }
      if m.kind == "close" then
        d.reason = null(m.reason)
      else
        d.body = m.body
      end
      messages[#messages + 1] = d
    end
    local anchors = {}
    for _, a in ipairs(t.anchors) do
      anchors[#anchors + 1] = {
        kind = a.kind,
        start = self:pos(a.start),
        ["end"] = self:pos(a["end"]),
        highlight = null(a.highlight),
      }
    end
    threads[#threads + 1] = {
      label = t.label,
      key = t.key,
      start_line = t.start,
      end_line = t["end"],
      state = M.state(t),
      duplicate = t.duplicate,
      messages = messages,
      anchors = anchors,
    }
  end
  local errors = {}
  for _, d in ipairs(self:errors()) do
    errors[#errors + 1] = { code = d.code, line = d.line }
  end
  return {
    spec = M.SPEC_VERSION,
    front_matter = { present = self.front_matter.present, autoremove_closed = self.front_matter.autoremove_closed },
    threads = threads,
    errors = errors,
  }
end

--- Thread containing 1-based row, or nil.
function Document:thread_at(row)
  for _, t in ipairs(self.threads) do
    if row >= t.start and row <= t["end"] then
      return t
    end
  end
end

--- Thread by label (key match); returns thread or nil, err.
function Document:find(label)
  local key = M.label_key(label)
  local found
  for _, t in ipairs(self.threads) do
    if t.key == key then
      if found then
        return nil, ("label %q is duplicated"):format(label)
      end
      found = t
    end
  end
  if not found then
    return nil, ("no thread labelled %q"):format(label)
  end
  return found
end

M.Document = Document
M.is_blank = is_blank
M.quote_match = quote_match
M.header_label = header_label
return M
