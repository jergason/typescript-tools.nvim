local c = require "typescript-tools.protocol.constants"
local utils = require "typescript-tools.protocol.utils"

-- TODO: read configuration
---@param params table
---@return TsserverRequest
local function configure(params)
  local text_document = params.textDocument

  return {
    command = c.CommandTypes.Configure,
    arguments = {
      file = vim.uri_to_fname(text_document.uri),
      formatOptions = {
        tabSize = 2,
        indentSize = 2,
        convertTabsToSpaces = true,
        newLineCharacter = "\n",
        insertSpaceAfterCommaDelimiter = true,
        insertSpaceAfterConstructor = false,
        insertSpaceAfterSemicolonInForStatements = true,
        insertSpaceBeforeAndAfterBinaryOperators = true,
        insertSpaceAfterKeywordsInControlFlowStatements = true,
        insertSpaceAfterFunctionKeywordForAnonymousFunctions = true,
        insertSpaceBeforeFunctionParenthesis = false,
        insertSpaceAfterOpeningAndBeforeClosingNonemptyParenthesis = false,
        insertSpaceAfterOpeningAndBeforeClosingNonemptyBrackets = false,
        insertSpaceAfterOpeningAndBeforeClosingNonemptyBraces = true,
        insertSpaceAfterOpeningAndBeforeClosingEmptyBraces = true,
        insertSpaceAfterOpeningAndBeforeClosingTemplateStringBraces = false,
        insertSpaceAfterOpeningAndBeforeClosingJsxExpressionBraces = false,
        insertSpaceAfterTypeAssertion = false,
        placeOpenBraceOnNewLineForFunctions = false,
        placeOpenBraceOnNewLineForControlBlocks = false,
        semicolons = "ignore",
      },
      preferences = {
        quotePreference = "auto",
        importModuleSpecifierEnding = "auto",
        jsxAttributeCompletionStyle = "auto",
        allowTextChangesInNewFiles = true,
        providePrefixAndSuffixTextForRename = true,
        allowRenameOfImportPath = true,
        includeAutomaticOptionalChainCompletions = true,
        provideRefactorNotApplicableReason = true,
        generateReturnInDocTemplate = true,
        includeCompletionsForImportStatements = true,
        includeCompletionsWithSnippetText = true,
        includeCompletionsWithClassMemberSnippets = true,
        includeCompletionsWithObjectLiteralMethodSnippets = true,
        useLabelDetailsInCompletionEntries = true,
        allowIncompleteCompletions = true,
        displayPartsForJSDoc = true,
        includeInlayParameterNameHints = "none",
        includeInlayParameterNameHintsWhenArgumentMatchesName = false,
        includeInlayFunctionParameterTypeHints = false,
        includeInlayVariableTypeHints = false,
        includeInlayPropertyDeclarationTypeHints = false,
        includeInlayFunctionLikeReturnTypeHints = false,
        includeInlayEnumMemberValueHints = false,
      },
    },
    skip_response = true,
  }
end

-- tsserver protocol reference:
-- https://github.com/microsoft/TypeScript/blob/29cbfe9a2504cfae30bae938bdb2be6081ccc5c8/lib/protocol.d.ts#L1305
---@param params table
---@return TsserverRequest
local function open_request(params)
  local text_document = params.textDocument

  return {
    command = c.CommandTypes.UpdateOpen,
    arguments = {
      openFiles = {
        {
          file = vim.uri_to_fname(text_document.uri),
          fileContent = text_document.text,
          scriptKindName = utils.get_text_document_script_kind(text_document),
        },
      },
      changedFiles = {},
      closedFiles = {},
    },
  }
end

---@param _ string
---@param params table
---@return TsserverRequest | TsserverRequest[], function|nil
local function did_open_creator(_, params)
  return {
    configure(params),
    open_request(params),
  }
end

return did_open_creator
