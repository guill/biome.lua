local biome = {}

local state = {
    biomes = {},
    dirty = false,
    active = {},
    shadowed = {},
    sorted_dirty = true,
    sorted_cache = {}
}

local function resort_biomes()
    -- Do a topological sort of the biomes
    local sorted = { "none" }
    local open = {}
    local dependencies = {}

    for name, def in pairs(state.biomes) do
        for _, parent in ipairs(def.parents or {}) do
            if ( state.biomes[parent] ) then
                dependencies[parent] = (dependencies[parent] or 0) + 1
            end
        end
    end

    for name in pairs(state.biomes) do
        local deps = dependencies[name]
        if not deps or deps == 0 then
            table.insert(open, name)
        end
    end

    while #open > 0 do
        local name = table.remove(open)
        table.insert(sorted, name)
        dependencies[name] = nil
        for _, parent in ipairs(state.biomes[name].parents or {}) do
            if dependencies[parent] then
                dependencies[parent] = dependencies[parent] - 1
                if dependencies[parent] == 0 then
                    table.insert(open, parent)
                end
            end
        end
    end

    if next(dependencies) then
        error(string.format('Biome dependency cycle detected: %s', vim.inspect(dependencies)))
    end

    -- Add any parents that aren't actually defined
    local virtual = {}
    for name, def in pairs(state.biomes) do
        for _, parent in ipairs(def.parents or {}) do
            if not virtual[parent] and not state.biomes[parent] then
                virtual[parent] = true
                table.insert(sorted, parent)
            end
        end
    end

    table.insert(sorted, "any")

    state.sorted_cache = sorted
    state.sorted_dirty = false
end

function biome.recalculate_biomes()
    if state.sorted_dirty then
        resort_biomes()
    end

    local active = {}
    local shadowed = {}
    for i=1, #state.sorted_cache do
        local name = state.sorted_cache[i]
        local def = state.biomes[name] or {}
        if active[name] or (def.test and def.test()) then
            active[name] = active[name] or "test"
            for _, parent in ipairs(def.parents or {}) do
                active[parent] = "parent"
            end
        end
        if active[name] or shadowed[name] then
            for _, shadow in ipairs(def.shadows or {}) do
                shadowed[shadow] = shadowed[shadow] or name
            end
        end
    end

    if not next(active) then
        active.none = "implicit"
    end
    active.any = "implicit"

    state.active = active
    state.shadowed = shadowed
    state.dirty = false
end

function biome.register_biome(name, test, parents, shadows)
    if state.biomes[name] then
        error('Biome ' .. name .. ' already exists')
    end
    state.biomes[name] = {
        test = test,
        parents = parents,
        shadows = shadows,
    }
    state.sorted_dirty = true
    state.dirty = true
end

function biome.unregister_biome(name)
    if state.biomes[name] then
        state.sorted_dirty = true
        state.dirty = true
    end
    state.biomes[name] = nil
end

function biome.in_biome(name)
    if state.dirty then
        biome.recalculate_biomes()
    end
    return not not state.active[name]
end

function biome.is_shadowed(name)
    if state.dirty then
        biome.recalculate_biomes()
    end
    return not not state.shadowed[name]
end

function biome.load_plugins()
    if state.dirty then
        biome.recalculate_biomes()
    end
    for i=#state.sorted_cache, 1, -1 do
        local name = state.sorted_cache[i]
        if state.active[name] and not state.shadowed[name] then
            local paths1 = vim.api.nvim_get_runtime_file('biomelua/' .. name .. '/*.lua', true)
            local paths2 = vim.api.nvim_get_runtime_file('biomelua/' .. name .. '.lua', true)
            local paths = vim.list_extend(paths1, paths2)
            for _, path in ipairs(paths) do
                vim.cmd('luafile "' .. path .. '"')
            end
        end
    end
end

function biome.print_active_biomes()
    if state.dirty then
        biome.recalculate_biomes()
    end
    for i=1, #state.sorted_cache do
        local name = state.sorted_cache[i]
        if state.active[name] then
            local str = string.format("%s [%s]%s", name, state.active[name], state.shadowed[name] and " (shadowed)" or "")
            print(str)
        end
    end
    return state.active
end

function biome.setup(opt)
    opt = vim.tbl_deep_extend(
        'force',
        {
            load_plugins = true,
        },
        opt or {}
    )
    if opt.biomes then
        for k, v in pairs(opt.biomes) do
            if v then -- Allow nil to disable a biome
                biome.register_biome(k, v.test, v.parents, v.shadows)
            end
        end
    end
    if opt.load_plugins then
        biome.load_plugins()
    end
end

return biome
