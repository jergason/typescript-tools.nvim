local log = require "vim.lsp.log"
local Process = require "typescript-tools.process"
local RequestQueue = require "typescript-tools.request_queue"
local handle_progress = require "typescript-tools.protocol.progress"
local module_mapper = require "typescript-tools.protocol.module_mapper"
local c = require "typescript-tools.protocol.constants"
local protocol = require "typescript-tools.protocol"

---@class PendingRequest: RequestContainer
---@field schedule boolean|nil
---@field cancelled boolean|nil

---@class Tsserver
---@field process Process
---@field request_queue RequestQueue
---@field pending_requests PendingRequest[]
---@field pending_diagnostic_seq number
---@field dispatchers Dispatchers

---@class Tsserver
local Tsserver = {}

---@param path table Plenary path object
---@param type ServerType
---@param dispatchers Dispatchers
---@return Tsserver
function Tsserver:new(path, type, dispatchers)
  local obj = {
    request_queue = RequestQueue:new(),
    pending_requests = {},
    requests_metadata = {},
    dispatchers = dispatchers,
  }

  setmetatable(obj, self)
  self.__index = self

  obj.process = Process:new(path, type, function(response)
    obj:handle_response(response)
  end, dispatchers.on_exit)

  return obj
end

---@param response table
function Tsserver:handle_response(response)
  local seq = response.request_seq

  P(response)

  handle_progress(response, self.dispatchers)

  if not seq then
    return
  end

  local metadata = self.requests_metadata[seq]

  if not metadata then
    return
  end

  local handler = metadata.handler

  coroutine.resume(handler, response.body or response)

  self.pending_requests[seq] = nil
  self.requests_metadata[seq] = nil

  self:send_queued_requests()
end

---@param method LspMethods | CustomMethods
---@param params table|nil
---@param callback LspCallback
---@param notify_reply_callback function|nil
function Tsserver:handle_request(method, params, callback, notify_reply_callback)
  local module = module_mapper.map_method_to_module(method)

  local ok, handler_module = pcall(require, "typescript-tools.protocol." .. module)

  if not ok or type(handler_module) ~= "table" then
    print(method, module)
    P(handler_module)
    return
  end

  local handler = coroutine.create(handler_module.handler)

  local function request(tsseever_request)
    return self.request_queue:enqueue {
      method = method,
      handler = handler,
      request = tsseever_request,
      interrupt_diagnostic = handler_module.interrupt_diagnostic,
    }
  end

  local function response(seq, lsp_response, error)
    local notify_reply = notify_reply_callback and vim.schedule_wrap(notify_reply_callback)
    local response_callback = callback and vim.schedule_wrap(callback)

    if notify_reply then
      notify_reply(seq)
    end

    if response_callback then
      if error then
        response_callback(error, error)
      else
        response_callback(nil, lsp_response)

        return true
      end
    end

    return false
  end

  coroutine.resume(handler, request, response, params)

  self:send_queued_requests()
end

---@private
function Tsserver:send_queued_requests()
  while vim.tbl_isempty(self.pending_requests) and not self.request_queue:is_empty() do
    local item = self.request_queue:dequeue()
    -- P(item)
    if not item then
      return
    end

    local request = vim.tbl_extend("force", {
      seq = item.seq,
      type = "request",
    }, item.request)

    self.process:write(request)

    self.pending_requests[item.seq] = true
    self.requests_metadata[item.seq] = item

    -- TODO:
  end
end

---@private
---@param method LspMethods | CustomMethods
---@param data table
function Tsserver:dispatch_update_event(method, data)
  if not (method == c.LspMethods.DidOpen or method == c.LspMethods.DidChange) then
    return
  end

  vim.schedule(function()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "TypescriptTools_" .. method,
      data = data,
    })
  end)
end

function Tsserver:terminate()
  self.process:terminate()
end

---@return boolean
function Tsserver:is_closing()
  return self.process:is_closing()
end

return Tsserver
