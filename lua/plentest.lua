local plentest_dir = vim.fn.fnamemodify(debug.getinfo(1).source:match('@?(.*[/\\])'), ':p:h:h:h')

local M = {}

local function write(s)
  io.stdout:write(s)
  io.stdout:write('\n')
end

local function test_paths(paths, opts)
  opts = vim.tbl_deep_extend('force', {
    nvim_cmd = vim.v.progpath,
    winopts = { winblend = 3 },
    sequential = false,
    keep_going = true,
    timeout = 50000, -- per file
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
    vim.system(job, { timeout = opts.timeout }, function(obj)
      -- Handle the result on the main loop, so that all output is written before the runner exits.
      vim.schedule(function()
        failure = failure or obj.code ~= 0
        write(obj.stderr or '')
        write(obj.stdout or '')
        if obj.code == 124 then
          write(('TIMEOUT after %d ms: %s'):format(opts.timeout, paths[i]))
        end
        jobs[i] = nil
      end)
    end)
  end

  -- Every file has its own timeout, so this ends once the last one is done or killed.
  vim.wait(2 ^ 31 - 1, function()
    return vim.tbl_isempty(jobs)
  end, 50)

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
