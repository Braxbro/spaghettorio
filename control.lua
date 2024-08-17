script.on_init(function()
    for _, surface in pairs(game.surfaces) do
        local mgs = surface.map_gen_settings
        mgs.property_expression_names["spaghettorio-rotation"] = "rotation-random"
        surface.map_gen_settings = mgs
    end
end)

script.on_event(defines.events.on_surface_created, function(data)
    local surface = game.surfaces[data.surface_index]
    local mgs = surface.map_gen_settings
        mgs.property_expression_names["spaghettorio-rotation"] = "rotation-random"
        surface.map_gen_settings = mgs
end)

local directionLookup = {[0] = "north","northeast","east","southeast","south","southwest","west","northwest"} -- used for debug

local exclude = {
    "straight-rail", "curved-rail", "rail", "gate", "rail-signal", "rail-chain-signal", "train-stop", -- rail stuff
    "transport-belt", "underground-belt", "splitter", "loader-1x1", "loader", "inserter", -- belt stuff
    "pipe-to-ground", -- underground pipes
    "offshore-pump", "pump" -- pumps
}

local function checkEntityMaskCollision(maskA, maskB)
    if maskA["not-colliding-with-itself"] and maskB["not-colliding-with-itself"] then -- if the masks are the same, they don't collide
        local match = true
        for index, _ in pairs(maskA) do
            if maskA[index] ~= maskB[index] then
                match = false
            end
        end
        if match then return false end
    elseif maskA["colliding-with-tiles-only"] or maskB["colliding-with-tiles-only"] then -- if one of the masks only cares about entities, they don't collide
        return false
    end
    for index, _ in pairs(maskA) do -- don't need to check maskB, because if it's not present in maskA then it doesn't collide by default
        if maskA[index] == maskB[index] then
            return true
        end
    end
    return false
end

script.on_event(defines.events.on_built_entity, function(data) -- handle rotation lock :3
    local player = game.players[data.player_index]
    local entity = data.created_entity
    for _, excluded in pairs(exclude) do
        if entity.type == excluded then return end -- If it's an excluded type, don't mess with it.
        if entity.type == "entity-ghost" then
            if entity.ghost_type == excluded then return end -- account for ghosts
        end
    end
    local requiredDirection = entity.surface.calculate_tile_properties({"spaghettorio-rotation"}, {entity.position})["spaghettorio-rotation"][1] -- ranges from 0 to 7
    if entity.has_flag("not-rotatable") then return end
    if not entity.has_flag("building-direction-8-way") then
        requiredDirection = math.floor(requiredDirection / 2) * 2 -- change range from 0 to 7 to 0, 2, 4, 6
    end
    if not entity.supports_direction then return end
    if entity.direction == requiredDirection then -- lock rotation and skip further steps if direction is correct
        entity.rotatable = false
        if hasDummy[data.player_index] then -- take away offset item
            player.cursor_stack.count = player.cursor_stack.count - 1
            hasDummy[data.player_index] = nil
        end
        return
    end
    if entity.type == "entity-ghost" then
        entity.direction = requiredDirection
        entity.rotatable = false
        if player.surface.entity_prototype_collides(entity.ghost_name, entity.position, false, entity.direction) then
            player.play_sound{path = "utility/cannot_build", position = entity.position}
            entity.destroy()
        else
            for _, otherEntity in pairs(player.surface.find_entities_filtered{
                type = "entity-ghost",
                area = entity.bounding_box
            }) do
                if entity ~= otherEntity then -- for once, comparing by reference is correct! lol
                    player.play_sound{path = "utility/cannot_build", position = entity.position}
                    entity.destroy()
                    return
                end
            end
        end
    else
        entity.direction = requiredDirection
        entity.rotatable = false
        for _, otherEntity in pairs(player.surface.find_entities_filtered{
            area = entity.bounding_box
        }) do
            if otherEntity.type == "entity-ghost" then
                otherEntity.destroy()
            elseif entity ~= otherEntity then -- for once, comparing by reference is correct! lol
                if checkEntityMaskCollision(entity.prototype.collision_mask, otherEntity.prototype.collision_mask) then
                    player.play_sound{path = "utility/cannot_build", position = entity.position}
                    player.mine_entity(entity)
                    return
                end
            end
        end
    end
end)

script.on_event(defines.events.on_gui_closed, function(data)
    if (not data.entity) or data.other_player then -- if it's not a non-player entity, skip handler
        return
    end
    local entity = data.entity
    for _, excluded in pairs(exclude) do
        if entity.type == excluded then return end -- If it's an excluded type, don't mess with it. Should never be true here, but I will include it just in case.
    end
    if entity.supports_direction and entity.rotatable then
        local requiredDirection = entity.surface.calculate_tile_properties({"spaghettorio-rotation"}, {entity.position})["spaghettorio-rotation"][1] -- ranges from 0 to 7
        if not entity.has_flag("building-direction-8-way") then -- This should be always true, but if for some reason Factorio adds an 8-way rotatable assembler or something... it doesn't hurt to cover that case.
            requiredDirection = math.floor(requiredDirection / 2) * 2 -- change range from 0 to 7 to 0, 2, 4, 6
        end
        --game.print(requiredDirection .. " " .. directionLookup[requiredDirection])
        entity.direction = requiredDirection
        entity.rotatable = false
    end
    if not entity.supports_direction then entity.rotatable = true end -- ensure that the above occurs even after resetting recipe to a non-rotatable one
end)

script.on_event(defines.events.on_entity_settings_pasted, function(data)
    local entity = data.destination
    for _, excluded in pairs(exclude) do
        if entity.type == excluded then return end -- If it's an excluded type, don't mess with it. Should never be true here, but I will include it just in case.
    end
    if entity.supports_direction and entity.rotatable then
        local requiredDirection = entity.surface.calculate_tile_properties({"spaghettorio-rotation"}, {entity.position})["spaghettorio-rotation"][1] -- ranges from 0 to 7
        if not entity.has_flag("building-direction-8-way") then -- This should be always true, but if for some reason Factorio adds an 8-way rotatable assembler or something... it doesn't hurt to cover that case.
            requiredDirection = math.floor(requiredDirection / 2) * 2 -- change range from 0 to 7 to 0, 2, 4, 6
        end
        --game.print(requiredDirection .. " " .. directionLookup[requiredDirection])
        entity.direction = requiredDirection
        entity.rotatable = false
    end
    if not entity.supports_direction then entity.rotatable = true end -- ensure that the above occurs even after resetting recipe to a non-rotatable one
end)