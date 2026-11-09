local M = {}

local function write(s)
  io.stdout:write(s)
  io.stdout:write('\n')
end

local KEYS = { 'Success', 'Failed', 'Errors', 'Pending' }

--- Add the counts from the `PLENTEST` line that `busted.format_results` prints to `totals`, and
--- return the output without that line.
local function count(totals, stdout)
  return (
    stdout:gsub('PLENTEST ([%d ]+)\n', function(counts)
      local i = 0
      for n in counts:gmatch('%d+') do
        i = i + 1
        totals[KEYS[i]] = totals[KEYS[i]] + tonumber(n)
      end
      return ''
    end)
  )
end

local function test_paths(paths, opts)
  opts = vim.tbl_deep_extend('force', {
    nvim_cmd = vim.v.progpath,
    sequential = false,
    timeout = 50000, -- per file
  }, opts or {})

  local function cmd(path)
    return {
      opts.nvim_cmd,
      '--headless',
      '--clean',
      '-u',
      opts.minimal_init,
      '-c',
      string.format('lua require("busted").run(%q)', vim.fs.abspath(path)),
    }
  end

  local failed, timed_out = {}, {}
  local totals = { Success = 0, Failed = 0, Errors = 0, Pending = 0 }
  local done = 0

  local function start(i)
    local path = paths[i]
    vim.system(cmd(path), { timeout = opts.timeout }, function(obj)
      -- Handle the result on the main loop, so that all output is written before the runner exits.
      vim.schedule(function()
        write(obj.stderr or '')
        write(count(totals, obj.stdout or ''))
        if obj.code == 124 then
          write(('TIMEOUT after %d ms: %s'):format(opts.timeout, path))
          table.insert(timed_out, path)
        elseif obj.code ~= 0 then
          table.insert(failed, path)
        end
        done = done + 1
        if opts.sequential and paths[i + 1] then
          start(i + 1)
        end
      end)
    end)
  end

  if opts.sequential then
    start(1)
  else
    for i = 1, #paths do
      start(i)
    end
  end

  -- Every file has its own timeout, so this ends once the last one is done or killed.
  vim.wait(2 ^ 31 - 1, function()
    return done == #paths
  end, 50)

  write(string.rep('=', 40))
  write(
    ('Files: %d, Success: %d, Failed: %d, Errors: %d, Pending: %d'):format(
      #paths,
      totals.Success,
      totals.Failed,
      totals.Errors,
      totals.Pending
    )
  )
  for _, p in ipairs(failed) do
    write('Failed file:    ' .. p)
  end
  for _, p in ipairs(timed_out) do
    write('Timed out file: ' .. p)
  end

  return vim.cmd((#failed > 0 or #timed_out > 0) and '1cq' or '0cq')
end

--- Run all `*_spec.lua` files in `directory` (or the spec file `directory` itself).
--- `opts.minimal_init` (required) must put plentest and the tested plugin on the 'runtimepath'.
function M.test_directory(directory, opts)
  if not (opts and opts.minimal_init) then
    write('plentest: opts.minimal_init is required')
    return vim.cmd('1cq')
  end
  print('Starting...')
  local paths
  if vim.fn.isdirectory(directory) == 1 then
    paths = vim.fs.find(function(name)
      return name:match('_spec%.lua$') ~= nil
    end, { path = directory, type = 'file', limit = math.huge })
    table.sort(paths)
  elseif vim.uv.fs_stat(directory) then
    paths = { directory }
  else
    paths = {}
  end

  if #paths == 0 then
    write('No spec files found in ' .. directory)
    return vim.cmd('1cq')
  end

  test_paths(paths, opts)
end

M.test_file = M.test_directory

return M
