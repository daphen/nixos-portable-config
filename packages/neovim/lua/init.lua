require("core.keymaps")
require("core.options")
require("notes-sync")

-- Skip in kitty-scrollback nvim — that's a pager, not an editor.
if vim.env.KITTY_SCROLLBACK_NVIM ~= "true" then
  require("ai-tracker").setup()
  require("hunk-nvim").setup()

  local map = vim.keymap.set
  map("n", "<C-g><C-g>", function() require("ai-tracker").show() end, { desc = "AI Tracker: changed files inbox" })
  map("n", "<C-g>t", function() require("ai-tracker").toggle_follow() end, { desc = "AI Tracker: toggle follow" })
  map("n", "<C-g>j", function() require("hunk-nvim.signs").next_hunk() end, { desc = "Next hunk" })
  map("n", "<C-g>k", function() require("hunk-nvim.signs").prev_hunk() end, { desc = "Prev hunk" })
end
