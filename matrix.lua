local ffi = require("ffi")
local cblas = require("cblas")

local CblasRowMajor = cblas.CblasRowMajor
local CblasNoTrans = cblas.CblasNoTrans
local CblasTrans = cblas.CblasTrans

local matrix_mt = { }

-- parts:
--
-- always defined:
-- 'form', 'm', 'n': form type (integer), rows and columns
--
-- defined for blas1 and blas2 forms:
-- 'beta' and 'c': scalar multiplier and matrix data
--
-- defined for blas2 only:
-- 'k', 'alpha', 'a', 'b', 'tra', 'trb': inner product dimension, scalar multiplier,
-- matrix data for first and second multiplier. Transpose cblas flags.
--
-- forms:
-- 0, blas0, zero matrix
-- 1, blas1, matrix 'c' with multiplier 'beta'
-- 2, blas2, gemm product with 'a', 'b' and multiplicands
--

local function matrix_new_zero(m, n)
    local mat = {
        ronly = false,
        tr    = CblasNoTrans,
        form  = 0,
        tra   = CblasNoTrans,
        trb   = CblasNoTrans,
        m     = m,
        n     = n,
        k     = 1,
        alpha = 0,
        a     = 0,
        b     = 0,
        beta  = 0,
        c     = 0,
    }
    setmetatable(mat, matrix_mt)
    return mat
end

local function matrix_alloc_form1(m, n)
    local mat = {
        ronly = false,
        tr    = CblasNoTrans,
        form  = 1,
        tra   = CblasNoTrans,
        trb   = CblasNoTrans,
        m     = m,
        n     = n,
        k     = 1,
        alpha = 0,
        a     = 0,
        b     = 0,
        beta  = 1,
        c     = ffi.new('double[?]', m * n),
    }
    setmetatable(mat, matrix_mt)
    return mat
end

local function matrix_new(m, n, init)
    if not init then
        return matrix_new_zero(m, n)
    elseif type(init) == "function" then
        local a = matrix_alloc_form1(m, n)
        for i = 0, m - 1 do
            local index_row = i * n
            for j = 0, n - 1 do
                a.c[index_row + j] = init(i, j)
            end
        end
        return a
    elseif type(init) == 'table' then
        local a = matrix_alloc_form1(m, n)
        for i = 0, m - 1 do
            local index_row = i * n
            for j = 0, n - 1 do
                a.c[index_row + j] = init[index_row + j + 1]
            end
        end
        return a
    else
        error("init argument should be a function or a table")
    end
end

local function mat_size(a)
    if a.tr == CblasNoTrans then
        return a.m, a.n
    else
        return a.n, a.m
    end
end

local function mat_data_dup(m, n, data)
    local new_data = ffi.new('double[?]', m * n)
    for i = 0, m * n - 1 do
        new_data[i] = data[i]
    end
    return new_data
end

local function mat_data_dup_tr(tr, m, n, data)
    local new_data = ffi.new('double[?]', m * n)
    if tr == CblasTrans then
        local new_m, new_n = n, m
        for i = 0, m - 1 do
            for j = 0, n - 1 do
                new_data[j * new_n + i] = data[i * n + j]
            end
        end
        return CblasNoTrans, new_m, new_n, new_data
    else
        -- MAYBE: transform double loop into a simple one
        for i = 0, m - 1 do
            for j = 0, n - 1 do
                new_data[i * n + j] = data[i * n + j]
            end
        end
        return CblasNoTrans, m, n, new_data
    end
end

local function mat_data_tr(m, n, data)
    -- In theory transpose could be done in place but the
    -- algorithm is complex and mostly inefficient. See:
    --
    -- https://en.wikipedia.org/wiki/In-place_matrix_transposition
    --
    local new_data = ffi.new('double[?]', m * n)
    local new_m, new_n = n, m
    for i = 0, m - 1 do
        for j = 0, n - 1 do
            new_data[j * new_n + i] = data[i * n + j]
        end
    end
    return new_m, new_n, new_data
end

local function mat_data_new_zero(m, n)
    local new_data = ffi.new('double[?]', m * n)
    for i = 0, m * n - 1 do
        new_data[i] = 0
    end
    return new_data
end

-- If the matrix is read-only make it writable by copying
-- the c data in newly allocated arrays.
-- TODO: rename to a better name (fox example ?)
-- FORMAL: keep matrix state valid
local function mat_dup(a)
    if not a.ronly then return end
    local m, n, k = a.m, a.n, a.k
    -- form2 always owns c data and do not own a and b datas.
    if a.form == 1 then
        a.c = mat_data_dup(m, n, a.c)
    end
    a.ronly = false
end

-- FORMAL: return a matrix in a valid state
local function matrix_copy(a, duplicate)
    local m, n, k = a.m, a.n, a.k
    local b = {
        ronly = not duplicate,
        tr    = a.tr,
        form  = a.form,
        tra   = a.tra,
        trb   = a.tra,
        m     = m,
        n     = n,
        k     = k,
        alpha = a.alpha,
        a     = a.a,
        b     = a.b,
        beta  = a.beta,
        c     = a.c,
    }
    if duplicate then
        mat_dup(a)
    end
    setmetatable(b, matrix_mt)
    return b
end

local function matrix_inspect(a)
    print "{"
    for i, name in pairs({"ronly", "tr", "form", "tra", "trb", "m", "n", "k", "alpha", "a", "b", "beta", "c"}) do
        print(string.format("    %s = %s", name, tostring(a[name])))
    end
    print "}"
end

local function null_form2_terms(a)
    a.k = 1
    a.alpha = 0
    a.a = 0
    a.b = 0
end

-- Transform matrix into form1.
-- CHECK: Do we really need to transform form0 to form1 ? verify
-- function usage. ANSWER: from mat_mul we really need to have
-- writeable actual c data. No, not really because if matrix is zero
-- mat_mul will return zero without calling GEMM.
-- ANSWER: ok from matrix_get, not called when form0.
-- FORMAL: keep matrix state valid
-- FORMAL: at the end ensure will be in form1
local function mat_compute_form1(a)
    if a.form == 0 then
        if a.tr == CblasTrans then
            a.tr = CblasNoTrans
            a.m, a.n = a.n, a.m
        end
        a.form = 1
        a.beta = 1
        a.c = mat_data_new_zero(a.m, a.n)
        null_form2_terms(a)
    elseif a.form == 2 then
        -- form 2 always has writeable c data.
        a.form = 1
        a.beta = 1
        local m, n, k = a.m, a.n, a.k
        cblas.cblas_dgemm(CblasRowMajor, a.tra, a.trb, m, n, k, a.alpha, a.a, a.tra == CblasNoTrans and k or m, a.b, a.trb == CblasNoTrans and n or k, a.beta, a.c, n)
        null_form2_terms(a)
    end
end

-- Reduce to fully computed form1 (beta = 1).
-- The transpose flag will not change.
-- FORMAL: keep matrix state valid
-- FORMAL: at the end matriw will be form1 with beta == 1
local function mat_compute(a)
    if a.form == 1 then
        if a.beta ~= 1 then
            mat_dup(a)
            local n = a.n
            for i = 0, m - 1 do
                cblas.cblas_dscal(n, a.beta, a.c + i * n, 1)
            end
            a.beta = 1
        end
    else
        -- CHECK: do we really need to transform form0 ?
        -- ANSWER: yes when used from matrix_set
        mat_compute_form1(a)
    end
end

-- FORMAL: returns a matrix in a valid state
local function mat_mul(a, b)
    local m, ka = mat_size(a)
    local kb, n = mat_size(b)
    if ka ~= kb then
        error('matrix dimensions mismatch in multiplication')
    end
    if a.form == 0 or b.form == 0 then
        return matrix_new(m, n)
    end
    mat_compute_form1(a)
    mat_compute_form1(b)

    local r = {
        ronly = false,
        tr    = CblasNoTrans,
        form  = 2,
        tra   = a.tr,
        trb   = b.tr,
        m     = m,
        n     = n,
        k     = ka,
        alpha = a.beta * b.beta,
        a     = a.c,
        b     = b.c,
        beta  = 0,
        c     = mat_data_new_zero(m, n),
    }
    setmetatable(r, matrix_mt)
    return r
end

local function mat_scalar_mul(a, alpha)
    local b = matrix_copy(a, false)
    if b.form == 1 then
        b.beta = b.beta * alpha
    elseif b.form == 2 then
        b.alpha = b.alpha * alpha
        b.beta = b.beta * alpha
    end
    return b
end

local function matrix_mul(a, b)
    if type(a) == 'number' then
        return mat_scalar_mul(b, a)
    elseif type(b) == 'number' then
        return mat_scalar_mul(a, b)
    else
        return mat_mul(a, b)
    end
end

local function mat_element_index(a, i, j)
    if a.tr == CblasNoTrans then
        return i * a.n + j
    else
        return j * a.n + i
    end
end

local function matrix_get(a, i, j)
    if a.form == 0 then
        return 0
    elseif a.form == 2 then
        mat_compute_form1(a)
    end
    local index = mat_element_index(a, i, j)
    return a.beta * a.c[index]
end

local function matrix_set(a, i, j, value)
    mat_compute(a)
    local index = mat_element_index(a, i, j)
    a.c[index] = value
end

local function flip_tr(tr)
    return tr == CblasTrans and CblasNoTrans or CblasTrans
end

local function matrix_transpose(a)
    a.tr = flip_tr(a.tr)
end

local function matrix_new_transpose(a)
    local b = matrix_copy(a, false)
    b.tr = flip_tr(b.tr)
    return b
end

local matrix_index = {
    size = mat_size,
    get = matrix_get,
    set = matrix_set,
    inspect = matrix_inspect,
    transpose = matrix_transpose,
}

matrix_mt.__mul = matrix_mul
matrix_mt.__index = matrix_index

return {
    new = matrix_new,
    transpose = matrix_new_transpose,
}
