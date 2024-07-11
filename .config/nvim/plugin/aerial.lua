local icons = require('rockyz.icons')
require('aerial').setup({
  backends = { 'lsp', 'treesitter', 'markdown', 'asciidoc', 'man' },
  layout = {
    max_width = 50,
    min_width = 50,
  },
  -- Press "?" in Aerial win to see the help showing all the available keymaps
  keymaps = {
    ["g?"] = "",
    ["<C-x>"] = "actions.jump_split",
    ["<C-s>"] = "",
    ["o"] = "",
    ["O"] = "",
    ["l"] = "",
    ["L"] = "",
    ["h"] = "",
    ["H"] = "",
    ["zX"] = "",
  },
  filter_kind = false, -- don't filter out any kinds
  icons = vim.tbl_extend('keep', icons.symbol_kinds, { Collapsed = icons.caret.caret_right }),
  show_guides = true,
  nav = {
    border = vim.g.border_style,
    max_height = 0.85,
    min_height = 0.85,
    win_opts = {
      winblend = 0,
    },
    preview = true,
    keymaps = {
      ["<C-x>"] = "actions.jump_split",
      ["<C-s>"] = "",
      ["q"] = "actions.close",
    },
  },
  -- Automatically open for man
  open_automatic = function(bufnr)
    return vim.bo[bufnr].filetype == 'man'
  end,
})

-- Toggle
vim.keymap.set('n', 'yoo', '<Cmd>AerialToggle<CR>')
-- Jump
vim.keymap.set('n', '[o', '<Cmd>AerialPrev<CR>')
vim.keymap.set('n', ']o', '<Cmd>AerialNext<CR>')
