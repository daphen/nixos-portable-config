-- Force .mdx files into their own filetype so render-markdown can target them
-- without fighting markview on plain markdown. Done at module-require time
-- (i.e. startup, when lz.n loads the plugins module) so the FileType event
-- has the right filetype to fire on.
vim.filetype.add({
  extension = {
    mdx = "mdx",
  },
})

return {
  "render-markdown.nvim",
  ft = { "mdx" },
  after = function()
    require("render-markdown").setup({
      file_types = { "mdx" },
    })

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "mdx",
      callback = function()
        vim.opt_local.conceallevel = 2
        vim.opt_local.concealcursor = ""
      end,
    })
  end,
}
