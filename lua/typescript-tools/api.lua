local c = require "typescript-tools.protocol.constants"
local plugin_config = require "typescript-tools.config"

local M = {}

---@param error_codes table - table of all diagnostic codes
---@param fix_names table
---@param bufnr integer
local function send_batch_code_action(error_codes, fix_names, bufnr)
  local clients = vim.lsp.get_active_clients {
    name = plugin_config.plugin_name,
    bufnr = bufnr,
  }

  if #clients == 0 then
    return
  end

  local typescript_client = clients[1]

  local params = {
    diagnostics = vim.diagnostic.get(bufnr),
    bufnr = bufnr,
    error_codes = error_codes,
    fix_names = fix_names,
  }

  typescript_client.request(c.CustomMethods.BatchCodeActions, params, function(err, res)
    if not err then
      vim.lsp.util.apply_workspace_edit(res.edit, "utf-8")
    end
  end, 0)
end

---@param mode OrganizeImportsMode
function M.organize_imports(mode)
  local params = { file = vim.api.nvim_buf_get_name(0), mode = mode }

  vim.lsp.buf_request(0, c.CustomMethods.OrganizeImports, params)
end

function M.go_to_source_definition()
  local params = vim.lsp.util.make_position_params()

  params.context = { source_definition = true }

  vim.lsp.buf_request(0, c.LspMethods.Definition, params, function(err, result, context)
    if not err then
      vim.lsp.handlers[c.LspMethods.Definition](err, result, context)
    end
  end)
end

function M.remove_unused()
  local UNUSED_VARIABLE_CODES = { 6196, 6133 }
  local FIX_NAMES = { "unusedIdentifier" }

  send_batch_code_action(UNUSED_VARIABLE_CODES, FIX_NAMES, 0)
end

function M.add_missing_imports()
  local MISSING_IMPORT_CODES = { 2552, 2304 }
  local FIX_NAMES = { "import" }

  send_batch_code_action(MISSING_IMPORT_CODES, FIX_NAMES, 0)
end

function M.fix_all()
  local FIXABLE_ERROR_CODES = { 2420, 1308, 7027 }
  local FIX_NAMES =
    { "fixClassIncorrectlyImplementsInterface", "fixAwaitInSyncFunction", "fixUnreachableCode" }

  send_batch_code_action(FIXABLE_ERROR_CODES, FIX_NAMES, 0)
end

---@param callback fun(params: table, result: table)|nil
function M.request_diagnostics(callback)
  local text_document = vim.lsp.util.make_text_document_params()
  local client = vim.lsp.get_active_clients {
    name = plugin_config.plugin_name,
    bufnr = vim.uri_to_bufnr(text_document.uri),
  }

  if #client == 0 then
    return
  end

  vim.lsp.buf_request(0, c.CustomMethods.Diagnostic, {
    textDocument = text_document,
  }, callback)
end

--- Returns an |lsp-handler| that filters TypeScript diagnostics with the given codes.
--- <pre>lua
--- local api = require('typescript-tools.api')
--- require('typescript-tools').setup {
---   handlers = {
---     -- Ignore 'This may be converted to an async function' diagnostics.
---     ['textDocument/publishDiagnostics'] = api.filter_diagnostics { 80006 }
---   }
--- }
--- </pre>
---
---@param codes integer[]
function M.filter_diagnostics(codes)
  vim.tbl_add_reverse_lookup(codes)
  return function(err, res, ctx, config)
    local filtered = {}
    for _, diag in ipairs(res.diagnostics) do
      if diag.source == "tsserver" and codes[diag.code] == nil then
        table.insert(filtered, diag)
      end
    end

    res.diagnostics = filtered
    vim.lsp.diagnostic.on_publish_diagnostics(err, res, ctx, config)
  end
end

return M
