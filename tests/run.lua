-- Headless test runner: nvim --headless -u NONE -l tests/run.lua [pattern]
-- Fixtures come from markdown-thread (the spec repo):
-- $MDTHREAD_FIXTURES, default ../markdown-thread/fixtures next to this repo.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.swapfile = false
package.path = root .. "/tests/?.lua;" .. package.path

local fixtures = vim.env.MDTHREAD_FIXTURES or vim.fn.fnamemodify(root .. "/../markdown-thread/fixtures", ":p")
fixtures = fixtures:gsub("/$", "")
if vim.fn.isdirectory(fixtures) == 0 then
  io.stderr:write("fixtures not found: " .. fixtures .. " (set MDTHREAD_FIXTURES)\n")
  os.exit(2)
end

local T = { fixtures = fixtures, root = root }
local results = { pass = 0, fail = 0 }
local current

function T.eq(got, want, what)
  if not vim.deep_equal(got, want) then
    error(("%s\n  want: %s\n  got:  %s"):format(what or "values differ", vim.inspect(want), vim.inspect(got)), 2)
  end
end

function T.ok(cond, what)
  if not cond then
    error(what or "assertion failed", 2)
  end
end

function T.read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

function T.glob(pattern)
  return vim.fn.glob(fixtures .. "/" .. pattern, false, true)
end

local cases = {}
function T.case(name, fn)
  cases[#cases + 1] = { name = name, fn = fn }
end

local filter = arg and arg[1]
local files = vim.fn.glob(root .. "/tests/test_*.lua", false, true)
for _, f in ipairs(files) do
  local mod = dofile(f)
  mod(T)
end

for _, c in ipairs(cases) do
  if not filter or c.name:find(filter, 1, true) then
    current = c.name
    local ok, err = xpcall(c.fn, debug.traceback)
    if ok then
      results.pass = results.pass + 1
      print("PASS " .. c.name)
    else
      results.fail = results.fail + 1
      print("FAIL " .. c.name .. "\n" .. tostring(err))
    end
  end
end
print(("%d passed, %d failed"):format(results.pass, results.fail))
os.exit(results.fail == 0 and 0 or 1)
