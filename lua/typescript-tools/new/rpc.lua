local api = vim.api
local util = require "lspconfig.util"
local configs = require "lspconfig.configs"
local plugin_config = require "typescript-tools.config"
local Path = require "plenary.path"

local Tsserver = require "typescript-tools.new.tsserver"
local autocommands = require "typescript-tools.new.autocommands"
local custom_handlers = require "typescript-tools.new.custom_handlers"

local M = {}

---@param dispatchers Dispatchers
---@return LspInterface
function M.start(dispatchers)
  local config = configs[plugin_config.NAME]
  local bufnr = api.nvim_get_current_buf()
  local bufname = api.nvim_buf_get_name(bufnr)

  assert(util.bufname_valid(bufname), "Invalid buffer name!")

  local root_dir = config.get_root_dir(util.path.sanitize(bufname), bufnr)
  local tsserver_path = Path:new(root_dir, "node_modules", "typescript", "lib", "tsserver.js")

  local npm_global_path = vim.fn
    .system([[node -p "require('path').resolve(process.execPath, '../..')"]])
    :match "^%s*(.-)%s*$"
  plugin_config.set_global_npm_path(npm_global_path)

  -- INFO: if we can't find local tsserver try to use global installed one
  if not tsserver_path:exists() then
    tsserver_path = Path:new(npm_global_path, "bin", "tsserver")
  end

  -- INFO: if there is no local or global tsserver just error out
  assert(
    tsserver_path:exists(),
    "Cannot find tsserver executable in local project nor global npm installation."
  )

  local tsserver = Tsserver:new(tsserver_path, dispatchers)

  autocommands.setup_autocommands()
  custom_handlers.setup_lsp_handlers(dispatchers)

  return {
    request = function(...)
      return tsserver:handle_request(...)
    end,
    notify = function(...)
      tsserver:handle_request(...)
    end,
    terminate = function()
      tsserver:terminate()
    end,
    is_closing = function()
      return tsserver:is_closing()
    end,
  }
end

return M