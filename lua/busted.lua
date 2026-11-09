local dirname = function(p)
  return vim.fn.fnamemodify(p, ':h')
end

local function get_trace(level, msg)
  local thisdir = dirname(debug.getinfo(1, 'Sl').source)
  local info = debug.getinfo(level, 'Sl')
  while
    info.what == 'C'
    or info.short_src:match('luassert[/\\].*%.lua$')
    or (info.source:sub(1, 1) == '@' and thisdir == dirname(info.source))
  do
    level = level + 1
    info = debug.getinfo(level, 'Sl')
  end

  local traceback = debug.traceback('', level)
  local index = traceback:find('\n%s*%[C]')
  return msg .. '\n' .. traceback:sub(1, index)
end

local function handler(msg)
  return get_trace(3, msg)
end

-- We are shadowing print so people can reliably print messages
print = function(...)
  for _, v in ipairs({ ... }) do
    io.stdout:write(tostring(v))
    io.stdout:write('\t')
  end

  io.stdout:write('\r\n')
end

local mod = {}

local results = { pass = {}, fail = {}, errs = {}, pending = {} }
local current_description = {}
local current_before_each = {}
local current_after_each = {}

local add_description = function(desc)
  table.insert(current_description, desc)

  return vim.deepcopy(current_description)
end

local pop_description = function()
  current_description[#current_description] = nil
end

local add_new_each = function()
  current_before_each[#current_description] = {}
  current_after_each[#current_description] = {}
end

local clear_last_each = function()
  current_before_each[#current_description] = nil
  current_after_each[#current_description] = nil
end

local call_inner = function(desc, func)
  local desc_stack = add_description(desc)
  add_new_each()
  local ok, msg = xpcall(func, handler)
  clear_last_each()
  pop_description()

  return ok, msg, desc_stack
end

local color_table = {
  yellow = 33,
  green = 32,
  red = 31,
}

local color_string = function(color, str)
  return string.format(
    '%s[%sm%s%s[%sm',
    string.char(27),
    color_table[color] or 0,
    str,
    string.char(27),
    0
  )
end

local SUCCESS = color_string('green', 'Success')
local FAIL = color_string('red', 'Fail')
local PENDING = color_string('yellow', 'Pending')

local HEADER = string.rep('=', 40)

local indent = function(msg, spaces)
  if spaces == nil then
    spaces = 4
  end

  local prefix = string.rep(' ', spaces)
  return prefix .. msg:gsub('\n', '\n' .. prefix)
end

mod.format_results = function(res)
  print('')
  print(color_string('green', 'Success: '), #res.pass)
  print(color_string('red', 'Failed : '), #res.fail)
  print(color_string('red', 'Errors : '), #res.errs)
  print(color_string('yellow', 'Pending: '), #res.pending)
  print(HEADER)
  -- machine-readable counts for the runner (plentest.lua), which strips this line
  io.stdout:write(('PLENTEST %d %d %d %d\n'):format(#res.pass, #res.fail, #res.errs, #res.pending))
end

mod.describe = function(desc, func)
  local ok, msg, desc_stack = call_inner(desc, func)

  if not ok then
    table.insert(results.errs, {
      descriptions = desc_stack,
      msg = msg,
    })
  end
end

mod.before_each = function(fn)
  table.insert(current_before_each[#current_description], fn)
end

mod.after_each = function(fn)
  table.insert(current_after_each[#current_description], fn)
end

mod.clear = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
end

--- Run the hooks of all levels: outermost first, or innermost first if `reverse`.
local run_each = function(tbl, reverse)
  local first, last, step = 1, #tbl, 1
  if reverse then
    first, last, step = last, first, -1
  end
  for i = first, last, step do
    for _, fn in ipairs(tbl[i] or {}) do
      fn()
    end
  end
end

mod.it = function(desc, func)
  local ok, msg, desc_stack = call_inner(desc, function()
    run_each(current_before_each)
    func()
  end)
  local after_ok, after_msg = xpcall(run_each, handler, current_after_each, true)
  if ok and not after_ok then
    ok, msg = false, after_msg
  end

  local test_result = {
    descriptions = desc_stack,
    msg = nil,
  }

  -- TODO: We should figure out how to determine whether
  -- and assert failed or whether it was an error...

  local to_insert
  if not ok then
    to_insert = results.fail
    test_result.msg = msg

    print(FAIL, '||', table.concat(test_result.descriptions, ' '))
    print(indent(msg, 12))
  else
    to_insert = results.pass
    print(SUCCESS, '||', table.concat(test_result.descriptions, ' '))
  end

  table.insert(to_insert, test_result)
end

mod.pending = function(desc)
  local curr_stack = vim.deepcopy(current_description)
  table.insert(curr_stack, desc)
  print(PENDING, '||', table.concat(curr_stack, ' '))
  table.insert(results.pending, { descriptions = curr_stack })
end

describe = mod.describe
it = mod.it
pending = mod.pending
before_each = mod.before_each
after_each = mod.after_each
clear = mod.clear
---@type Luassert
assert = require('luassert')

mod.run = function(file)
  file = file:gsub('\\', '/')

  print('\n' .. HEADER)
  print('Testing: ', file)

  local loaded, msg = loadfile(file)

  if not loaded then
    print(HEADER)
    print('FAILED TO LOAD FILE')
    print(color_string('red', msg))
    print(HEADER)
    return vim.cmd('2cq')
  end

  coroutine.wrap(function()
    local ok, err = xpcall(loaded, handler)
    if not ok then
      print(HEADER)
      print('ERROR OUTSIDE OF DESCRIBE')
      print(color_string('red', err))
      print(HEADER)
      return vim.cmd('2cq')
    end

    mod.format_results(results)

    if #results.errs ~= 0 then
      print('Unexpected errors:')
      for _, e in ipairs(results.errs) do
        print(FAIL, '||', table.concat(e.descriptions, ' '))
        print(indent(e.msg, 12))
      end
      return vim.cmd('2cq')
    elseif #results.fail > 0 then
      print('Tests Failed. Exit: 1')
      return vim.cmd('1cq')
    else
      return vim.cmd('0cq')
    end
  end)()
end

return mod
