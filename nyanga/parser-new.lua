local parse_block

local LJ_52 = false

--[[
var_lookup
expr
err_syntax
expr_field
expr_bracket
expr_str
parse_args
err_token
lex_opt
]]

local function token2str(tk)
    if string.match(tk, "^TK_") then
        return string.sub(tk, 4)
    else
        return tk
    end
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

local function expr_primary(ast, ls)
    local v
    if ls.token == '(' then
        local line = ls.linenumber
        ls:next()
        local _ = expr(ast, ls)
        lex_match(ls, ')', '(', line)
        -- discarge the resulting expression
    elseif ls.token == 'TK_name' or (not LJ_52 and ls.token == 'TK_goto') then
        v = var_lookup(ast, ls)
    else
        err_syntax(ls, "unexpected symbol")
    end
    while true do
        if ls.token == '.' then
            v = expr_field(ast, ls)
        elseif ls.token == '[' then
            local key = expr_bracket(ast, ls)
            v = ast:expr_index(v, key)
        elseif ls.token == ':' then
            ls:next()
            local key = expr_str(ast, ls)
            local args = parse_args(ast, ls)
            v = ast:expr_method_call(v, key, args)
        elseif ls.token == '(' or ls.token == 'TK_string' or ls.token == '{' then
            local args = parse_args(ast, ls)
            v = ast:expr_function_call(v, args)
        else
            break
        end
    end
end

local function parse_assignment(ast, ls, vlist, var, vk)
    checkcond(ls, vk >= VLOCAL and vk <= VINDEXED, 'syntax error')
    ast:add_assign_lhs_var(vlist, var)
    if ls:opt(',') then
        local n_var, n_vk = expr_primary(ast, ls)
        parse_assignment(ast, ls, vlist, n_var, n_vk)
    else -- Parse RHS.
        ls:check('=')
        local els = expr_list(ast, ls)
        ast:add_assign_exprs(els)
    end
end

local function parse_call_assign(ast, ls)
    local var, vk = expr_primary(ast, ls)
    if vk == VCALL then
        return ast:new_statement_expr(var)
    else
        local vlist = ast:new_assignment()
        parse_assignment(ast, ls, vlist)
        return vlist
    end
end

local function parse_while(ast, ls, line)
    ls:next() -- Skip 'while'.
    local cond = expr_cond(ast, ls)
    ls:check()
    local b = parse_block(ast, ls)
    lex_match(ls, 'TK_end', 'TK_while', line)
    return ast:new_while_statement(cond, b)
end

local function parse_then(ast, ls, if_stmt)
    ls:next()
    local cond = expr_cond(ast, ls)
    ls:check('TK_then')
    local b = parse_block(ast, ls)
    ast:add_if_then_block(if_stmt, cond, b)
end

local function parse_if(ast, ls, line)
    local if_stmt = ast:new_if_statement()
    parse_then(ast, ls, if_stmt)
    while ls.token == 'TK_elseif' do
        parse_then(ast, ls, if_stmt)
    end
    if ls.token == 'TK_else' then
        ls:next() -- Skip 'else'.
        local b = parse_block(ast, ls)
        ast:add_if_else_block(if_stmt, b)
    end
    lex_match(ls, 'TK_end', 'TK_if', line)
    return if_stmt
end

local StatementRule = {
    ['TK_if']    = parse_if,
    ['TK_while'] = parse_while,
}

local IsLastStatement = {
    ['TK_return'] = true,
    ['TK_break']  = true,
}

local function parse_stmt(ast, ls)
    local line = ls.linenumber
    local parse_rule = StatementRule[ls.token]
    if parse_rule then
        local islast = IsLastStatement[ls.token]
        local stmt = parse_rule(ast, ls, line)
        return stmt, islast
    else
        local stmt = parse_call_assign(ast, ls)
        return stmt, false
    end
end

function parse_block(ast, ls)
    local islast = false
    local chunk = ast:new_block()
    while not islast and not endofblock(ls.token) do
        stmt, islast = parse_stmt(ast, ls)
        chunk:add(stmt)
        ls:opt(';')
    end
    return chunk
end

local function parse(ast, ls)
    ls:next()
    local chunk = parse_block(ast, ls)
end
