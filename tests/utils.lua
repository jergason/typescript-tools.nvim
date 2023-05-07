local M = {}

function M.wait_for_lsp_initialization()
  if not _G.initialized then
    vim.wait(10000, function()
      return _G.initialized
    end, 10)
    -- to be sure everything is setup correctly wait a bit
    vim.wait(1000)
  end
end

---@param file string
---@param command string|nil
function M.open_file(file, command)
  command = command or "e"

  local cwd = vim.fn.getcwd()

  if not string.find(cwd, "ts_project", 1, true) then
    vim.cmd ":cd tests/ts_project"
  end

  vim.cmd(command .. " " .. file)
end

function M.get_text_document()
  return { uri = vim.uri_from_bufnr(0) }
end

---@param line number
---@param character number
function M.make_position(line, character)
  return { line = line, character = character }
end

---@param start_line number
---@param start_character number
---@param end_line number
---@param end_character number
function M.make_range(start_line, start_character, end_line, end_character)
  return {
    start = M.make_position(start_line, start_character),
    ["end"] = M.make_position(end_line, end_character),
  }
end

function M.tsv(options)
  return options[vim.env.TEST_TYPESCRIPT_VERSION] or options.default
end

return M
