# plentest.nvim

Lightweight self-contained busted-style testing harness for Neovim.

Forked from [plenary.test_harness](https://github.com/nvim-lua/plenary.nvim?tab=readme-ov-file#plenarytest_harness) with vendored [luassert](https://github.com/lunarmodules/luassert) and [say](https://github.com/lunarmodules/say).

**Not for public use.** (Check out https://github.com/lewis6991/nvim-test instead.)

## Usage

```sh
PLENTEST=path/to/plentest.nvim nvim --headless --clean -u scripts/minimal_init.lua \
  -c "lua require('plentest').test_directory('tests', { minimal_init = './scripts/minimal_init.lua' })"
```

where `scripts/minimal_init.lua` puts `$PLENTEST` and the tested plugin (`.`) on the `runtimepath`.

- `test_directory(path, opts)` runs every `*_spec.lua` file under `path` (or the spec file `path`),
  each in its own `nvim --headless --clean` process. `test_file(path, opts)` is the same.
- `opts.minimal_init` (required): init file for the test processes (`-u`).
- `opts.timeout`: per file, in ms (default 50000). A file that runs longer is killed and reported.
- `opts.sequential`: run the files one after another instead of in parallel.
- `opts.nvim_cmd`: Nvim binary for the test processes (default `v:progpath`).

The runner prints each file's output, then the totals and the failed or timed-out files. It exits 1 if
any file failed, errored or timed out, or if no spec file was found.

Spec files can use `describe`, `it`, `pending`, `before_each`, `after_each` and `assert` (luassert).
