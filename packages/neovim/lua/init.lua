-- Core setup (loaded before plugins)
require("core.keymaps")
require("core.options")
require("notes-sync")

-- ai-tracker is a local lua module (not an lz.n plugin — it lives on rtp,
-- not packpath/opt). Skip in kitty-scrollback nvim instances; those are
-- pagers, not editors, and shouldn't react to AI edits.
if vim.env.KITTY_SCROLLBACK_NVIM ~= "true" then
  require("ai-tracker").setup({
    log_file = vim.fn.expand("~/.local/share/nvim/ai-changes.jsonl"),
    max_entries = 1000,
    auto_reload = true,
  })

  local map = vim.keymap.set

  -- Main interfaces
  map("n", "<C-g><C-g>", function() require("ai-tracker").show() end, { desc = "AI Changes (by file)" })
  map("n", "<C-g>a",     function() require("ai-tracker").show_all_lines() end, { desc = "AI Changes (all lines)" })
  map("n", "<C-g>p",     function() require("ai-tracker").show_grouped() end, { desc = "AI Changes (grouped by prompt)" })
  map("n", "<C-g>P",     function() require("ai-tracker").show_prompt_files() end, { desc = "AI Prompts & Files" })

  -- Hunk navigation / diff preview (delegated to gitsigns since we use git diffs now)
  map("n", "<C-g>j", function() require("gitsigns").next_hunk() end,            { desc = "Next hunk" })
  map("n", "<C-g>k", function() require("gitsigns").prev_hunk() end,            { desc = "Previous hunk" })
  map("n", "<C-g>d", function() require("gitsigns").preview_hunk_inline() end,  { desc = "Preview hunk (inline)" })
  map("n", "<C-g>u", function() require("ai-tracker").jump_to_unread() end,     { desc = "Jump to first unread AI edit" })
  map("n", "<C-f>",  function() require("ai-tracker").jump_to_latest() end,     { desc = "Jump to latest AI edit" })
  map("n", "<C-g>r", function() require("ai-tracker").reset_tracking() end,     { desc = "Reset AI tracking (manual clear)" })

  -- Preview gate / Claude integration
  map("n", "<C-g>t",       function() require("ai-tracker.preview").toggle() end,           { desc = "Toggle AI Tracker preview gate" })
  map("n", "<C-g><leader>", function() require("ai-tracker.preview").toggle_pause() end,     { desc = "Pause/resume Claude tool calls" })
  map("n", "<C-g>y",       function() require("ai-tracker.preview").ask_about_chunk() end,  { desc = "Send chunk + question to Claude" })
  map("n", "<C-g>o",       function() require("gitsigns").toggle_linehl() end,              { desc = "Toggle git diff overlay (linehl)" })
  map("n", "]g",           function() require("ai-tracker.preview").next_chunk() end,       { desc = "Next AI chunk / git hunk" })
  map("n", "[g",           function() require("ai-tracker.preview").prev_chunk() end,       { desc = "Prev AI chunk / git hunk" })

  -- Manual annotation + cleanup
  map("n", "<leader>ap", function() require("ai-tracker").annotate_prompt() end,    { desc = "Annotate AI prompt" })
  map("n", "<leader>ac", function() require("ai-tracker").clear_clean_files() end,  { desc = "Clear AI tracking for clean files" })
  map("n", "<leader>aR", function() require("ai-tracker").reset_tracking() end,     { desc = "Reset AI tracking (new feature)" })
end

-- Remaining plugins are loaded via lz.n from nvimWrapper's initLua spec:
--   require('lz.n').load('plugins')
--   require('lz.n').load('plugins.lsp')
-- No lazy.nvim bootstrap needed — plugins are pre-installed by nix.
