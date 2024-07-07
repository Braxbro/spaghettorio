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
    "offshore-pump", "pump" -- pumps
}

local hasDummy = {} -- shouldn't in theory desync, since it doesn't exist except during the placement process

script.on_event(defines.events.on_pre_build, function(data) -- check if placement needs to be refunded
    local player = game.players[data.player_index]
    if player.cursor_ghost or data.shift_build then return end -- if it's placing a ghost, don't do anything; that's handled when the ghost is actually created
    if not player.cursor_stack.prototype then return end
    if player.is_cursor_blueprint() then 
        player.clear_cursor()
        return
    end
    local toPlace = player.cursor_stack.prototype.place_result
    for _, excluded in pairs(exclude) do
        if toPlace.type == excluded then return end -- If it's an excluded type, don't mess with it.
    end
    ---@diagnostic disable-next-line: need-check-nil
    if toPlace.has_flag("not-rotatable") or not toPlace.supports_direction then return end
    local requiredDirection = player.surface.calculate_tile_properties({"spaghettorio-rotation"}, {data.position})["spaghettorio-rotation"][1] -- ranges from 0 to 7
    ---@diagnostic disable-next-line: need-check-nil
    if not toPlace.has_flag("building-direction-8-way") then -- If, for some reason, this is causing a nil index exception, someone else was an idiot.
        requiredDirection = math.floor(requiredDirection / 2) * 2 -- change range from 0 to 7 to 0, 2, 4, 6
    end
    --game.print(requiredDirection .. " " .. directionLookup[requiredDirection])
    if data.direction == requiredDirection then return end -- skip refund if the direction is already correct
    if (not player.can_build_from_cursor{
        position = data.position,
        direction = requiredDirection,
        alt = data.shift_build,
        terrain_building_size = 1})
        or data.direction ~= requiredDirection
        then
        player.cursor_stack.count = player.cursor_stack.count + 1; -- offset destruction of invalid entities
        hasDummy[data.player_index] = true;
    end
end)

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
    if not entity.supports_direction then
        if hasDummy[data.player_index] then -- take away offset item
            player.cursor_stack.count = player.cursor_stack.count - 1
            hasDummy[data.player_index] = nil
        end
        return
    end
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
                end
            end
        end
    else
        local args = {
            position = entity.position,
            direction = requiredDirection,
            alt = false,
            terrain_building_size = 1
        }
        if not player.can_build_from_cursor(args) then
            player.play_sound{path = "utility/cannot_build", position = entity.position}
        end
        entity.destroy()
        hasDummy[data.player_index] = nil
        player.build_from_cursor(args)
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