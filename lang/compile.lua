local lex_setup = require('lexer')
local parse = require('parser')
local ast_builder = require('lua-ast')
local reader = require('reader')

-- Two kind of backend can be used to generate the code from the AST:
-- - "generator", generates LuaJIT bytecode
-- - "luacode-generator", generates Lua code
--
-- Both can be used interchangeably, they take the AST tree and produce
-- a string that can be passed to the function "loadstring".
-- In the case of the bytecode generator the string will be actually a
-- binary blob that corresponds to the generated bytecode.
local generator = require('generator')

local function lang_toolkit_error(msg)
   if string.sub(msg, 1, 9) == "LLT-ERROR" then
        return false, string.sub(msg, 10)
    else
        error(msg, 0) -- Raise an error without line informations
    end
end

local function compile(reader, filename, options)
    local ls = lex_setup(reader, filename)
    local ast = ast_builder.New()
    local parse_success, tree = pcall(parse, ast, ls)
    if not parse_success then
        return lang_toolkit_error(tree)
    end
    local success, luacode = pcall(generator, tree, filename)
    if not success then
        return lang_toolkit_error(luacode)
    end
    return true, luacode
end

local function lang_loadstring(src, filename, options)
    reader.string_init(src)
    return compile(reader.string, filename, options)
end

local function lang_loadfile(filename, options)
    reader.file_init(filename)
    return compile(reader.file, filename, options)
end

return lang_loadstring, lang_loadfile
