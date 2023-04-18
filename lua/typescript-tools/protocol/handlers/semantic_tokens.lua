local constants = require "typescript-tools.protocol.constants"
local utils = require "typescript-tools.protocol.utils"
local bit = require "bit"

local TOKEN_ENCODING_TYPE_OFFSET = 8
local TOKEN_ENCODING_MODIFIER_MASK = bit.lshift(1, TOKEN_ENCODING_TYPE_OFFSET) - 1

local NEWLINE_LENGTH_MAP = {
  dos = 2,
  unix = 1,
  mac = 1,
}

-- Returns { [linenr]: [utf-16 line length] } table for every line in buffer
-- @param bufnr
-- @returns table
local function get_buffer_lines_lengths(bufnr)
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, vim.api.nvim_buf_line_count(bufnr), false)
  local newline_length = NEWLINE_LENGTH_MAP[vim.bo.fileformat]

  return vim.tbl_map(function(line)
    return vim.lsp.util._str_utfindex_enc(line, nil, "utf-16") + newline_length
  end, all_lines)
end

-- Given the buffer offset finds nvim line and character position in UTF-16 encoding
-- could not use `vim.api.nvim_buf_get_offset` because it returns byte offset and
-- tsserver uses character offset. Uses offset_from_last_iteration and line_from_last_iteration
-- for performance. Tokens in tsserver response are positioned in ascending order so we don't need
-- to search whole file every token.
-- @param offset
-- @param lines_offsets - table with every line in buffer offsets
-- @param offset_from_last_iteration - offset to start with (performance)
-- @param line_from_last_iteration - line to start with (performance)
-- @returns lsp compatible spans
local function get_character_position_at_offset(
  offset,
  lines_lengths,
  offset_from_last_iteration,
  line_from_last_iteration
)
  if #lines_lengths == 1 then
    return { line = 0, character = offset }
  end

  local current_offset = offset_from_last_iteration

  for line = line_from_last_iteration, #lines_lengths, 1 do
    local current_line_length = lines_lengths[line + 1]
    local offset_with_current_line = current_offset + current_line_length

    if offset_with_current_line > offset then
      return { line = line, character = offset - current_offset }, current_offset
    end

    current_offset = offset_with_current_line
  end
end

-- Transforms the semantic token spans given by the ts-server into lsp compatible spans.
-- @param spans the spans given by ts-server
-- @param requested_bufnr
-- @returns lsp compatible spans
local function transform_spans(spans, requested_bufnr)
  local lsp_spans = {}
  local previous_line = 0
  local previous_token_start = 0
  local previous_offset = 0
  local lines_lengths = get_buffer_lines_lengths(requested_bufnr)

  for i = 1, #spans, 3 do
    -- ts-server sends us a packed array that contains 3 elements per 1 token:
    -- 1. the start offset of the token
    -- 2. length of the token
    -- 3. token type & modifier packed into a bitset
    local token_start_offset = spans[i]
    local token_length = spans[i + 1]
    local token_type_bit_set = spans[i + 2]

    -- unpack the modifier and type: https://github.com/microsoft/TypeScript/blob/main/src/services/classifier2020.ts#L45
    local token_modifier = bit.band(token_type_bit_set, TOKEN_ENCODING_MODIFIER_MASK)
    local token_type = bit.rshift(token_type_bit_set, TOKEN_ENCODING_TYPE_OFFSET) - 1

    local pos, last_line_offset = get_character_position_at_offset(
      token_start_offset,
      lines_lengths,
      previous_offset,
      previous_line
    )
    local line, character = pos.line, pos.character

    -- lsp spec requires 5 elements per token instead of 3:
    -- 1. delta line number (relative to the previous line)
    -- 2. delta token start offset (relative to the previous token)
    -- 3. length of the token
    -- 4. type of the token (e.g. function, comment, enum etc.)
    -- 5. token modifier (static, async etc.)
    local delta_line = line - previous_line
    local delta_start = previous_line == line and character - previous_token_start or character

    table.insert(lsp_spans, delta_line)
    table.insert(lsp_spans, delta_start)
    table.insert(lsp_spans, token_length)
    table.insert(lsp_spans, token_type)
    table.insert(lsp_spans, token_modifier)

    previous_token_start = character
    previous_line = line
    previous_offset = last_line_offset
  end

  return lsp_spans
end

-- tsserver protocol reference:
-- https://github.com/microsoft/TypeScript/blob/v5.0.2/src/server/protocol.ts#L879
local semantic_tokens_full_request_handler = function(_, params)
  local text_document = params.textDocument
  local start_offset = 0
  local requested_bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  local end_offset = utils.get_offset_at_position(
    { vim.api.nvim_buf_line_count(requested_bufnr), 0 },
    requested_bufnr
  )

  return {
    command = constants.CommandTypes.EncodedSemanticClassificationsFull,
    arguments = {
      file = vim.uri_to_fname(text_document.uri),
      start = start_offset,
      length = end_offset - start_offset,
      format = "2020",
    },
  }
end

-- tsserver protocol reference:
-- https://github.com/microsoft/TypeScript/blob/v5.0.2/src/server/protocol.ts#L910
local semantic_tokens_full_response_handler = function(_, body, request_params)
  local requested_bufnr = vim.uri_to_bufnr(request_params.textDocument.uri)

  return { data = transform_spans(body.spans, requested_bufnr) }
end

return {
  request = {
    method = constants.LspMethods.SemanticTokensFull,
    handler = semantic_tokens_full_request_handler,
  },
  response = {
    method = constants.CommandTypes.EncodedSemanticClassificationsFull,
    handler = semantic_tokens_full_response_handler,
    schedule = true,
  },
}
