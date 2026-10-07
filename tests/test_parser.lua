-- Conformance: the Lua parser reproduces markdown-thread's fixtures exactly,
-- and reports the same implementation warnings as the reference parser.
local P = require("markdown-thread.parser")

-- Same table as markdown-thread/tests/test_fixtures.py (WARNINGS).
local WARNINGS = {
  ["basic"] = {},
  ["opener-forms"] = {},
  ["states"] = { "empty-thread" },
  ["labels"] = {},
  ["ordinary-quotes"] = { "nested-thread", "orphan-anchor", "orphan-anchor" },
  ["marker-fields"] = { "invalid-timestamp", "marker-ignored-text", "marker-ignored-text",
    "responder-marker-incomplete" },
  ["close-rule"] = { "close-without-blank" },
  ["code"] = {},
  ["anchors"] = { "orphan-anchor" },
  ["duplicates"] = {},
  ["lists"] = { "inconsistent-indent", "inconsistent-indent" },
  ["front-matter-yaml"] = {},
  ["front-matter-flow"] = {},
  ["front-matter-toml"] = {},
  ["link-definition"] = { "label-is-link" },
  ["boundaries"] = { "no-blank-before-thread", "lazy-continuation", "header-in-thread", "text-after-close" },
  ["crlf"] = {},
}

return function(T)
  T.case("parser: every fixture has expectations", function()
    local names = {}
    for _, f in ipairs(T.glob("parse/*.md")) do
      names[#names + 1] = vim.fn.fnamemodify(f, ":t:r")
    end
    table.sort(names)
    local want = vim.tbl_keys(WARNINGS)
    table.sort(want)
    T.eq(names, want, "parse fixtures vs WARNINGS table")
  end)

  for _, f in ipairs(T.glob("parse/*.md")) do
    local name = vim.fn.fnamemodify(f, ":t:r")
    T.case("parser: fixture " .. name, function()
      local doc = P.parse(T.read(f))
      local want = vim.json.decode(T.read(f:gsub("%.md$", ".json")), { luanil = { object = false, array = false } })
      T.eq(doc:to_json(), want, name .. ".json")
      local codes = {}
      for _, d in ipairs(doc.diagnostics) do
        if d.severity == "warning" then
          codes[#codes + 1] = d.code
        end
      end
      table.sort(codes)
      local w = vim.deepcopy(WARNINGS[name] or {})
      table.sort(w)
      T.eq(codes, w, name .. " warnings")
    end)
  end

  T.case("parser: marker fields table", function()
    local cases = {
      { "-->", "", {} },
      { "-->", " Alice Smith", { "Alice Smith" } },
      { "-->", " Alice @ 2026-10-06", { "Alice", "2026-10-06" } },
      { "-->", " @ 2026-10-06T10:00Z", { nil, "2026-10-06T10:00Z" } },
      { "-->", " @alice:example.org", { "@alice:example.org" } },
      { "-->", " alice@example.org", { "alice@example.org" } },
      { "-->", " Alice @2026-10-06", { "Alice", "2026-10-06" } },
      { "-->", " Alice @ soon", { "Alice", nil, nil, nil, "soon" } },
      { "-->", " Alice @ 2026-10-06 x", { "Alice", "2026-10-06", nil, "x" } },
      { "-->", " Alice ! not a reason", { "Alice ! not a reason" } },
      { "+++", " ! wontfix", { nil, nil, "wontfix" } },
      { "+++", " Alice @ 2026-10-06 ! a @ b", { "Alice", "2026-10-06", "a @ b" } },
      { "+++", " Alice! now", { "Alice! now" } },
      { "+++", " !", {} },
    }
    for _, c in ipairs(cases) do
      local n, ts, r, ig, bad = P.parse_fields(c[1], c[2])
      T.eq({ n, ts, r, ig, bad }, c[3], c[1] .. c[2])
    end
  end)

  T.case("parser: label key", function()
    T.eq(P.label_key("Why  Ticks"), "why ticks")
    T.eq(P.label_key("  why\n ticks "), "why ticks")
    T.eq(P.label_key("Ünïcode Ä"), "ünïcode ä")
    T.eq(P.label_key("   "), "")
  end)

  T.case("parser: timestamps", function()
    T.ok(P.is_full_timestamp("2026-10-06T19:57-04:00"))
    T.ok(P.is_full_timestamp("2026-10-06T19:57:05Z"))
    T.ok(not P.is_full_timestamp("2026-10-06"))
    T.ok(not P.is_full_timestamp("2026-10-06T19:57"))
    T.eq(P.timestamp_prefix("2026-10-06T19:57-04"), "2026-10-06T19:57")
  end)
end
