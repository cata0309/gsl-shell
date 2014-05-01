local build = require('syntax').build

local function is_ident(node)
    return node.kind == "Identifier"
end

local function is_binop(node, op)
    return node.kind == "BinaryExpression" and node.operator == op
end

local function is_unop(node, op)
    return node.kind == "UnaryExpression" and node.operator == op
end

local function literal(value)
    return build("Literal", { value = value })
end

local function op_eval(op, a, b)
    if     op == "+" then return a + b
    elseif op == "-" then return a - b
    elseif op == "*" then return a * b
    elseif op == "/" and b ~= 0 then return a / b
    elseif op == "^" then return a^b end
end

local function is_const(expr)
    if expr.kind == "Literal" and type(expr.value) == "number" then
        return expr.value
    elseif expr.kind == "BinaryExpression" then
        local a = is_const(expr.left)
        local b = is_const(expr.right)
        if a and b then return op_eval(expr.operator, a, b) end
    elseif expr.kind == "UnaryExpression" then
        local a = is_const(expr.argument)
        if a and expr.operator == "-" then return -a end
    end
end

local function binop(op, left, right)
    local lconst = is_const(left)
    local rconst = is_const(right)
    if lconst and rconst then
        local r = op_eval(op, lconst, rconst)
        if r then return literal(r) end
    elseif op == "*" then
        if lconst == 1 then
            return right
        elseif rconst == 1 then
            return left
        elseif lconst == 0 or rconst == 0 then
            return literal(0)
        end
    elseif op == "/" then
        if rconst == 1 then return left end
        if lconst == 0 and rconst and rconst ~= 0 then return literal(0) end
    elseif op == "+" then
        if lconst == 0 then
            return right
        elseif rconst == 0 then
            return left
        end
    elseif op == "-" then
        if rconst == 0 then
            return left
        elseif lconst == 0 then
            return build("UnaryExpression", { operator = op, argument = right })
        end
    end
    return build("BinaryExpression", { operator = op, left = left, right = right })
end

local function unop(op, arg)
    if op == "-" then
        local aconst = is_const(arg)
        if aconst then return literal(-aconst) end
    end
    return build("UnaryExpression", { operator = op, argument = arg })
end

local function linear_ctxfree(expr, var, ctx)
    if is_ident(expr) then
        print(">>> linear_ctxfree identifier", expr.name, var.name)
        if expr.name == var.name then
            return expr, true, 1
        else
            local for_local, outer_local, var_value = ctx(expr)
            if for_local and var_value then
                return linear_ctxfree(var_value, var, ctx)
            elseif outer_local then
                return expr, true, 0
            end
        end
    elseif is_const(expr) then
        return expr, true, 0
    elseif is_binop(expr, "+") then
        local aexp, alin, acoeff = linear_ctxfree(expr.left, var, ctx)
        local bexp, blin, bcoeff = linear_ctxfree(expr.right, var, ctx)
        if alin and blin then
           return binop("+", aexp, bexp), true, acoeff + bcoeff
        end
    elseif is_binop(expr, "-") then
        local aexp, alin, acoeff = linear_ctxfree(expr.left, var, ctx)
        local bexp, blin, bcoeff = linear_ctxfree(expr.right, var, ctx)
        if alin and blin then
           return binop("-", aexp, bexp), true, acoeff - bcoeff
        end
    elseif is_binop(expr, "*") then
        local aconst = is_const(expr.left)
        if aconst then
            local bexp, blin, bcoeff = linear_ctxfree(expr.right, var, ctx)
            if blin then return binop("*", literal(aconst), bexp), true, aconst * bcoeff end
        else
            local aexp, alin, acoeff = linear_ctxfree(expr.left, var, ctx)
            if alin then
                local bconst = is_const(expr.right)
                if bconst then return binop("*", aexp, literal(bconst)), true, acoeff * bconst end
            end
        end
    elseif is_binop(expr, "/") then
        local aexp, alin, acoeff = linear_ctxfree(expr.left, var, ctx)
        local bconst = is_const(expr.right)
        if bconst and alin then
            return binop("/", aexp, literal(bconst)), true, acoeff / bconst
        end
    elseif is_unop(expr, "-") then
        local aexp, alin, acoeff = linear_ctxfree(expr.argument, var, ctx)
        if alin then return unop("-", aexp), true, -acoeff end
    end
    return false
end

local function expr_is_context_free(expr, ctx)
    print(">>> expr_is_context_free", expr.kind)
    if is_ident(expr) then
        local for_local, outer_local, var_value = ctx(var)
        if for_local and var_value then
            return expr_is_context_free(var_value, ctx)
        elseif outer_local then
            return expr
        end
    elseif expr.kind == "Literal" then
        return expr
    elseif expr.kind == "BinaryExpression" then
        local a = expr_is_context_free(expr.left, ctx)
        local b = expr_is_context_free(expr.right, ctx)
        if a and b then return binop(expr.operator, a, b) end
    elseif expr.kind == "UnaryExpression" then
        local a = expr_is_context_free(expr.argument, ctx)
        if a then return unop(expr.operator, a) end
    elseif expr.kind == "MemberExpression" then
        print(">>> MemberExpression")
        local _, obj_outer = ctx(expr.object)
        print(">>> obj_outer", obj_outer)
        if obj_outer then
            local prop_outer = not expr.computed
            if expr.computed then
                _, prop_outer = ctx(expr.prop_outer)
            end
            print(">>> prop_outer", prop_outer)
            return prop_outer and expr
        end
    end
    return false
end

local function expr_eval(expr, var, value)
    if is_ident(expr) and expr.name == var.name then
        return value
    elseif expr.kind == "BinaryExpression" then
        local left = expr_eval(expr.left, var, value)
        local right = expr_eval(expr.right, var, value)
        return binop(expr.operator, left, right)
    elseif expr.kind == "UnaryExpression" then
        local arg = expr_eval(expr.argument, var, value)
        return unop(expr.operator, arg)
    else
        return expr
        -- TODO: scan MemberExpression
    end
end

return { is_const = is_const, linear_ctxfree = linear_ctxfree, context_free  = expr_is_context_free, eval = expr_eval }
