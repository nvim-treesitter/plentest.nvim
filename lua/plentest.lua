local plentest_dir = vim.fn.fnamemodify(debug.getinfo(1).source:match('@?(.*[/\\])'), ':p:h:h:h')

local M = {}

local outputter = vim.schedule_wrap(function(...)
  for _, v in ipairs({ ... }) do
    io.stdout:write(tostring(v))
    io.stdout:write('\n')
  end
end)

local function test_paths(paths, opts)
  opts = vim.tbl_deep_extend('force', {
    nvim_cmd = vim.v.progpath,
    winopts = { winblend = 3 },
    sequential = false,
    keep_going = true,
    timeout = 50000,
  }, opts or {})

  vim.env.PLENTEST_TIMEOUT = opts.timeout

  local failure = false
  local jobs = vim.tbl_map(function(p)
    local args = {
      opts.nvim_cmd,
      '--headless',
      '-c',
      'set rtp+=.,' .. vim.fn.escape(plentest_dir, ' '),
    }

    if opts.minimal_init then
      table.insert(args, '--clean')
      table.insert(args, '-u')
      table.insert(args, opts.minimal_init)
    end

    table.insert(args, '-c')
    table.insert(args, string.format('lua require("busted").run("%s")', vim.fs.abspath(p)))
    return args
  end, paths)

  for i, job in pairs(jobs) do
    vim.system(job, {}, function(obj)
      failure = failure or obj.code ~= 0
      outputter(obj.stderr)
      outputter(obj.stdout)
      jobs[i] = nil
    end)
  end
  vim.wait(opts.timeout, function()
    return vim.tbl_isempty(jobs)
  end)

  if failure then
    return vim.cmd('1cq')
  end

  return vim.cmd('0cq')
end

function M.test_directory(directory, opts)
  print('Starting...')
  local paths = vim.fs.find(function(name)
    return vim.glob.to_lpeg('*_spec.lua'):match(name)
  end, { path = directory, type = 'file', limit = math.huge })

  test_paths(paths, opts)
end

function M.test_file(filepath)
  test_paths({ filepath })
end

return M
