-- Plugins loaded
local modules = {
  "bqf",
  "cmp",
  "comment",
  "eregex",
  "fugitive",
  "gitsigns",
  "hlargs",
  "hlslens",
  "harpoon",
  "iswap",
  "indent-blankline",
  "lf",
  "lualine",
  "luasnip",
  "lsp.lsp-config",
  "netrw",
  "nvim-colorizer",
  "nvim-fundo",
  "nvim-navic",
  "nvim-navbuddy",
  "nvim-ufo",
  "project",
  "quick-scope",
  "registers",
  "tabline",
  "targets",
  "treesitter",
  "treesitter-context",
  "telescope.telescope-config",
  "test",
  "undotree",
  "vim-after-object",
  "vim-asterisk",
  "vim-floaterm",
  "vim-flog",
  "vim-gh-line",
  "vim-grepper",
  "vim-illuminate",
  "vim-matchup",
}
for _, module in ipairs(modules) do
  require("rockyz.plugin-config." .. module)
end
