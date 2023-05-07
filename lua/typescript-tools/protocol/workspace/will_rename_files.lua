local c = require "typescript-tools.protocol.constants"
local utils = require "typescript-tools.protocol.utils"

local M = {}

---@param code_edits table
---@return table<string, table>|nil
local function make_text_edits(code_edits)
  if not code_edits then
    return nil
  end

  local changes = {}

  for _, code_edit in ipairs(code_edits) do
    local uri = vim.uri_from_fname(code_edit.fileName)
    local text_edits = changes[uri] or {}

    for _, text_change in ipairs(code_edit.textChanges) do
      local text_edit = {
        newText = text_change.newText,
        range = utils.convert_tsserver_range_to_lsp(text_change),
      }
      table.insert(text_edits, text_edit)
    end

    changes[uri] = text_edits
  end

  return changes
end

---@type TsserverProtocolHandler
function M.handler(request, response, params)
  -- in params there could be multiple files but in order fulfill request
  -- with multiple files we would need to send multiple requests to tsserver
  -- at the moment there is no abstraction to do that so we just take first file
  local first_file = params.files[1]
  local old_file_path = vim.uri_to_fname(first_file.oldUri)
  local new_file_path = vim.uri_to_fname(first_file.newUri)

  -- tsserver protocol reference:
  -- https://github.com/microsoft/TypeScript/blob/29cbfe9a2504cfae30bae938bdb2be6081ccc5c8/lib/protocol.d.ts#L511
  request {
    command = c.CommandTypes.GetEditsForFileRename,
    arguments = {
      oldFilePath = old_file_path,
      newFilePath = new_file_path,
    },
  }

  local body = coroutine.yield()

  -- tsserver protocol reference:
  -- https://github.com/microsoft/TypeScript/blob/29cbfe9a2504cfae30bae938bdb2be6081ccc5c8/lib/protocol.d.ts#L511
  response {
    changes = make_text_edits(body),
  }
end

return M
