local c = require "typescript-tools.protocol.constants"
local utils = require "typescript-tools.protocol.utils"

---@param file string
---@param content_changes table
local function convert_text_changes(file, content_changes)
  local reversed_content_changes = {}

  -- INFO: tsserver weird beast it process changes in reversed order, but IDK in all cases this assumption is ok
  for _, change in ipairs(content_changes) do
    table.insert(
      reversed_content_changes,
      1,
      vim.tbl_extend(
        "force",
        { newText = change.text },
        utils.convert_lsp_range_to_tsserver(change.range)
      )
    )
  end

  return {
    fileName = file,
    textChanges = reversed_content_changes,
  }
end

-- tsserver protocol reference:
-- https://github.com/microsoft/TypeScript/blob/29cbfe9a2504cfae30bae938bdb2be6081ccc5c8/lib/protocol.d.ts#L1305
---@param _ string
---@param params table
---@return thread
local function did_open_handler(_, params)
  return coroutine.create(function()
    local text_document = params.textDocument
    local content_changes = params.contentChanges

    return {
      command = c.CommandTypes.UpdateOpen,
      arguments = {
        changedFiles = {
          convert_text_changes(vim.uri_to_fname(text_document.uri), content_changes),
        },
        closedFiles = {},
        openFiles = {},
      },
    }
  end)
end

return did_open_handler
