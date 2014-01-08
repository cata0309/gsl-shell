local LJ_52 = false

--[[
setmetatable(_G, {
    __index = function(t, x) error('undefined global ' .. x) end,
    __newindex = function(t, k, v) error('undefined global ' .. k) end
    }
)
--]]

local IsLastStatement = { TK_return = true, TK_break  = true }
local EndOfBlock = { TK_else = true, TK_elseif = true, TK_end = true, TK_until = true, TK_eof = true }

--[[
err_syntax
err_token
]]

local function checkcond(ls, cond, em)
    if not cond then err_syntax(ls, em) end
end

local function token2str(tok)
    return string.match(tok, "^TK_") and string.sub(tok, 4) or tok
end

local function lex_opt(ls, tok)
	if ls.token == tok then
		ls:next()
		return true
	end
	return false
end

local function lex_check(ls, tok)
	if ls.token ~= tok then err_token(ls, tok) end
	ls:next()
end

local function lex_match(ls, what, who, line)
    if not lex_opt(ls, what) then
        if line == ls.linenumber then
            err_token(ls, what)
        else
            lex_error(ls, ls.token, "%s expected (to close %s at line %d)", token2str(what), token2str(who), line)
        end
    end
end

local function lex_str(ls)
	if ls.token ~= 'TK_name' and (LJ_52 or ls.token ~= 'TK_goto') then
		err_token(ls, 'TK_name')
	end
	local s = ls.tokenval
	ls:next()
	return s
end

local expr_primary, expr, expr_unop, expr_binop, expr_simple
local expr_list, expr_table
local parse_body, parse_block, parse_args

local function var_lookup(ast, ls)
    local name = lex_str(ls)
    return ast:expr_var(name)
end

local function expr_field(ast, ls, v)
	ls:next() -- Skip dot or colon.
	local key = lex_str(ls)
	return ast:expr_property(v, key)
end

local function expr_bracket(ast, ls)
	ls:next() -- Skip '['.
	local v = expr(ast, ls)
	lex_check(ls, ']')
    return v
end

-- Priorities for each binary operator.
-- (left priority) * 256 + (right priority)
-- modulus is your friend
local BinOp = {
    ['+']  = 6 * 256 + 6, ['-']    = 6 * 256 + 6, ['*'] = 7 * 256 + 7, ['/'] = 7 * 256 + 7, ['%'] = 7 * 256 + 7,
    ['^']  = 10* 256 + 9, TK_concat= 5 * 256 + 4, -- POW CONCAT (right associative)
    TK_eq  = 3 * 256 + 3, TK_ne    = 3 * 256 + 3,
    ['<']  = 3 * 256 + 3, Tk_ge    = 3 * 256 + 3, ['>'] = 3 * 256 + 3, TK_le = 3 * 256 + 3,
    TK_and = 2 * 256 + 2, TK_or    = 1 * 256 + 1,
}

local UNARY_PRIORITY = 8

local function left_priority(op)
    return bit.rshift(op, 8)
end

local function right_priority(op)
    return bit.band(op, 0xff)
end

function expr_table(ast, ls)
    local line = ls.linenumber
    local hkeys, hvals = { }, { }
    local avals = { }
    lex_check(ls, '{')
    while ls.token ~= '}' do
        local key
        if ls.token == '[' then
            key = expr_bracket(ast, ls)
            lex_check(ls, '=')
        elseif (ls.token == 'TK_name' or (not LJ_52 and ls.token == 'TK_goto')) and ls:lookahead() == '=' then
            local name = lex_str(ls)
            key = ast:expr_string(name)
            lex_check(ls, '=')
        end
        local val = expr(ast, ls)
        if key then
            hkeys[#hkeys + 1] = key
            hvals[#hvals + 1] = val
        else
            avals[#avals + 1] = val
        end
        if not lex_opt(ls, ',') and not lex_opt(ls, ';') then break end
    end
    lex_match(ls, '}', '{', line)
    return ast:expr_table(avals, hkeys, hvals, line)
end

function expr_simple(ast, ls)
    local tk, val = ls.token, ls.tokenval
    local e
    if tk == 'TK_number' then
        e = ast:expr_number(val)
    elseif tk == 'TK_string' then
        e = ast:expr_string(val)
    elseif tk == 'TK_nil' then
        e = ast:expr_nil()
    elseif tk == 'TK_true' then
        e = ast:expr_boolean(true)
    elseif tk == 'TK_false' then
        e = ast:expr_boolean(false)
    elseif tk == 'TK_dots' then
        if not ls.fs.varargs then
            err_syntax(ls, "cannot use \"...\" outside a vararg function")
        end
        e = ast:expr_vararg()
    elseif tk == '{' then
        return expr_table(ast, ls)
    elseif tk == 'TK_function' then
        ls:next()
        local args, body, proto = parse_body(ast, ls, ls.linenumber, false)
        return ast:expr_function(args, body, proto, ls.linenumber)
    else
        return expr_primary(ast, ls)
    end
    ls:next()
    return e
end

function expr_list(ast, ls)
    local exps = { }
    exps[1] = expr(ast, ls)
    while lex_opt(ls, ',') do
        exps[#exps + 1] = expr(ast, ls)
    end
    return exps
end

function expr_unop(ast, ls)
    local tk = ls.token
    if tk == 'TK_not' or tk == '-' or tk == '#' then
        ls:next()
        local v = expr_binop(ast, ls, UNARY_PRIORITY)
        return ast:expr_unop(tk, v)
    else
        return expr_simple(ast, ls)
    end
end

-- Parse binary expressions with priority higher than the limit.
function expr_binop(ast, ls, limit)
	local v = expr_unop(ast, ls)
    local op = ls.token
    while BinOp[op] and left_priority(BinOp[op]) > limit do
        ls:next()
        local v2, nextop = expr_binop(ast, ls, right_priority(BinOp[op]))
        v = ast:expr_binop(op, v, v2)
        op = nextop
    end
    return v, op
end

function expr(ast, ls)
	return expr_binop(ast, ls, 0) -- Priority 0: parse whole expression.
end

-- Parse primary expression.
function expr_primary(ast, ls)
    local v, vk
    -- Parse prefix expression.
    if ls.token == '(' then
        local line = ls.linenumber
        ls:next()
        vk, v = 'expr', expr(ast, ls)
        lex_match(ls, ')', '(', line)
    elseif ls.token == 'TK_name' or (not LJ_52 and ls.token == 'TK_goto') then
        vk, v = 'var', var_lookup(ast, ls)
    else
        err_syntax(ls, "unexpected symbol")
    end
    while true do -- Parse multiple expression suffixes.
        if ls.token == '.' then
            vk, v = 'indexed', expr_field(ast, ls, v)
        elseif ls.token == '[' then
            local key = expr_bracket(ast, ls)
            vk, v = 'indexed', ast:expr_index(v, key)
        elseif ls.token == ':' then
            ls:next()
            local key = lex_str(ls)
            local args = parse_args(ast, ls)
            vk, v = 'call', ast:expr_method_call(v, key, args)
        elseif ls.token == '(' or ls.token == 'TK_string' or ls.token == '{' then
            local args = parse_args(ast, ls)
            vk, v = 'call', ast:expr_function_call(v, args)
        else
            break
        end
    end
    return v, vk
end

-- Parse statements ----------------------------------------------------


-- Parse 'return' statement.
local function parse_return(ast, ls, line)
    ls:next() -- Skip 'return'.
    ls.fs.has_return = true
    local exps
    if EndOfBlock[ls.token] or ls.token == ';' then -- Base return.
        exps = { }
    else -- Return with one or more values.
        exps = expr_list(ast, ls)
    end
    return ast:return_stmt(exps, line)
end

-- Parse function argument list.
function parse_args(ast, ls)
    local line = ls.linenumber
    local args
    if ls.token == '(' then
        if not LJ_52 and line ~= ls.lastline then
            err_syntax(ls, "ambiguous syntax (function call x new statement)")
        end
        ls:next()
        if ls.token ~= ')' then -- Not f().
            args = expr_list(ast, ls)
        end
        lex_match(ls, ')', '(', line)
    elseif ls.token == '{' then
        local a = expr_table(ast, ls)
        args = { a }
    elseif ls.token == 'TK_string' then
        local a = lex_str(ls)
        args = { ast:expr_string(a) }
    else
        err_syntax(ls, "function arguments expected")
    end
    return args
end

local function parse_assignment(ast, ls, vlist, var, vk)
    checkcond(ls, vk == 'var' or vk == 'indexed', 'syntax error')
    vlist[#vlist+1] = var
    if lex_opt(ls, ',') then
        local n_var, n_vk = expr_primary(ast, ls)
        return parse_assignment(ast, ls, vlist, n_var, n_vk)
    else -- Parse RHS.
        lex_check(ls, '=')
        local exps = expr_list(ast, ls)
        return ast:assignment_expr(vlist, exps, ls.linenumber)
    end
end

local function parse_call_assign(ast, ls)
    local var, vk = expr_primary(ast, ls)
    if vk == 'call' then
        return ast:new_statement_expr(var, ls.linenumber)
    else
        local vlist = { }
        return parse_assignment(ast, ls, vlist, var, vk)
    end
end

-- Parse 'local' statement.
local function parse_local(ast, ls)
    local line = ls.linenumber
    if lex_opt(ls, 'TK_function') then -- Local function declaration.
        local name = lex_str(ls)
        local args, body, proto = parse_body(ast, ls, ls.linenumber, false)
        return ast:local_function_decl(name, args, body, proto, line)
    else -- Local variable declaration.
        local vl = { }
        repeat -- Collect LHS.
            vl[#vl+1] = lex_str(ls)
        until not lex_opt(ls, ',')
        local exps
        if lex_opt(ls, '=') then -- Optional RHS.
            exps = expr_list(ast, ls)
        else
            exps = { }
        end
        return ast:local_decl(vl, exps, line)
    end
end

local function parse_func(ast, ls, line)
    local needself = false
    ls:next() -- Skip 'function'.
    -- Parse function name.
    local v = var_lookup(ast, ls)
    while ls.token == '.' do -- Multiple dot-separated fields.
        v = expr_field(ast, ls, v)
    end
    if ls.token == ':' then -- Optional colon to signify method call.
        needself = true
        v = expr_field(ast, ls, v)
    end
    local args, body, proto = parse_body(ast, ls, line, needself)
    return ast:function_decl(v, args, body, proto, line)
end

local function parse_while(ast, ls, line)
    ls:next() -- Skip 'while'.
    local cond = expr(ast, ls)
    lex_check(ls, 'TK_do')
    local body = parse_block(ast, ls)
    lex_match(ls, 'TK_end', 'TK_while', line)
    return ast:while_stmt(cond, body, ls.linenumber)
end

local function parse_then(ast, ls, branches)
    ls:next()
    local cond = expr(ast, ls)
    lex_check(ls, 'TK_then')
    local b = parse_block(ast, ls)
    branches[#branches + 1] = {cond, b}
end

local function parse_if(ast, ls, line)
    local branches = { }
    parse_then(ast, ls, branches)
    while ls.token == 'TK_elseif' do
        parse_then(ast, ls, branches)
    end
    local else_branch
    if ls.token == 'TK_else' then
        ls:next() -- Skip 'else'.
        else_branch = parse_block(ast, ls)
    end
    lex_match(ls, 'TK_end', 'TK_if', line)
    return ast:if_stmt(branches, else_branch, line)
end

local function parse_label(ast, ls)
    ls:next() -- Skip '::'.
    local name = lex_str(ls)
    lex_check(ls, 'TK_label')
    -- Recursively parse trailing statements: labels and ';' (Lua 5.2 only).
    while true do
        if ls.token == 'TK_label' then
            parse_label(ast, ls)
        elseif LJ_52 and ls.token == ';' then
            ls:next()
        else
            break
        end
    end
    return ast:label_stmt(name, ls.linenumber)
end

-- Parse a statement. Returns the statement itself and a boolean that tells if it
-- must be the last one in a chunk.
local function parse_stmt(ast, ls)
    local line = ls.linenumber
    local stmt
    if ls.token == 'TK_if' then
        stmt = parse_if(ast, ls, line)
    elseif ls.token == 'TK_while' then
        stmt = parse_while(ast, ls, line)
    elseif ls.token == 'TK_function' then
        stmt = parse_func(ast, ls, line)
    elseif ls.token == 'TK_local' then
        ls:next()
        stmt = parse_local(ast, ls, line)
    elseif ls.token == 'TK_return' then
        stmt = parse_return(ast, ls, line)
        return stmt, true -- Must be last.
    elseif ls.token == 'TK_break' then
        ls:next()
        stmt = ast:break_stmt(line)
        return stmt, not LJ_52 -- Must be last in Lua 5.1.
    elseif LJ_52 and ls.token == ';' then
        ls:next()
        return parse_stmt(ast, ls)
    elseif ls.token == 'TK_label' then
        stmt = parse_label(ast, ls)
    elseif ls.token == 'TK_goto' then
        if LJ_52 or ls:lookahead() == 'TK_name' then
            ls:next()
            stmt = parse_goto(ast, ls)
        end
    end
    -- If here 'stmt' is "nil" then ls.token didn't match any of the previous rules.
    -- Fall back to call/assign rule.
    if not stmt then
        stmt = parse_call_assign(ast, ls)
    end
    return stmt, false
end

local function parse_params(ast, ls, needself)
    lex_check(ls, '(')
    local args = { }
    if needself then
        args[1] = ast:expr_var("self")
    end
    if ls.token ~= ')' then
        repeat
            if ls.token == 'TK_name' or (not LJ_52 and ls.token == 'TK_goto') then
                args[#args+1] = var_lookup(ast, ls)
            elseif ls.token == 'TK_dots' then
                ls:next()
                ls.fs.varargs = true
            else
                err_syntax(ls, "<name> or \"...\" expected")
            end
        until not lex_opt(ls, ',')
    end
    lex_check(ls, ')')
    return args
end

local function new_proto(ls, varargs)
    return { varargs = varargs }
end

local function parse_chunk(ast, ls, top_level)
    local islast = false
    local body = { }
    while not islast and not EndOfBlock[ls.token] do
        local stmt
        stmt, islast = parse_stmt(ast, ls)
        body[#body + 1] = stmt
        lex_opt(ls, ';')
    end
    if top_level then
        return ast:chunk(body, ls.linenumber)
    else
        return ast:block_stmt(body, ls.linenumber)
    end
end

-- Parse body of a function.
function parse_body(ast, ls, line, needself)
    local pfs = ls.fs
    ls.fs = new_proto(ls, false)
    local args = parse_params(ast, ls, needself)
    local body = parse_chunk(ast, ls)
    local proto = ls.fs
    if ls.token ~= 'TK_end' then
        lex_match(ls, 'TK_end', 'TK_function', line)
    end
    ls:next()
    ls.fs = pfs
    return args, body, proto
end

function parse_block(ast, ls)
    return parse_chunk(ast, ls)
end

local function parse(ast, ls)
    ls.fs = new_proto(ls, true)
    local line = ls.linenumber
    ls:next()
    local args = { ast:expr_vararg(ast) }
    return parse_chunk(ast, ls, true)
end

return parse
