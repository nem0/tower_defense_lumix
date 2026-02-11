-- Hex grid creation script for Lumix Engine
-- Creates a 30x20 grid with mixed terrain (grass, water) surrounded by water border

local GRID_WIDTH = 30
local GRID_HEIGHT = 20
local HEX_SPACING_X = 2  -- Horizontal spacing between hex centers
local SQRT3 = 1.7320508075688772
local HEX_SPACING_Z = 2 * SQRT3 * 0.5  -- Vertical spacing between rows
local TREE_PROBABILITY = 0.75  -- Probability of placing a tree on each grass hex (0.0 to 1.0)
local MOUNTAIN_PROBABILITY = 0.1  -- Probability of placing a mountain on each grass hex (0.0 to 1.0)
local WATER_FEATURE_PROBABILITY = 0.03  -- Probability of converting a hex to water with features (0.0 to 1.0)
local MOUSE_WHEEL_ZOOM_MULTIPLIER = 30 -- How fast does mouse wheel zoom

local center_x = ((GRID_WIDTH - 1) * HEX_SPACING_X + (GRID_HEIGHT % 2) * (HEX_SPACING_X / 2)) / 2
local center_z = (GRID_HEIGHT - 1) * HEX_SPACING_Z / 2

-- Camera control variables
local camera_entity = nil
local camera_speed = 20.0  -- Units per second
local camera_zoom_speed = 10.0  -- Units per second
local camera_min_height = 10.0
local camera_max_height = 100.0
local camera_min_distance = 10.0
local camera_max_distance = 100.0

-- Camera movement boundaries (based on grid size with padding)
local camera_min_x = center_x - 40  -- Allow some padding beyond grid
local camera_max_x = center_x + 40
local camera_min_z = center_z - 30
local camera_max_z = center_z + 30

-- Input state variables
local move_left = 0
local move_right = 0
local move_forward = 0
local move_back = 0
local zoom_in = 0
local zoom_out = 0
local zoom_wheel = 0

-- Mouse panning variables
local mouse_panning = false
local last_mouse_x = 0
local last_mouse_y = 0
local pan_sensitivity = 0.03  -- Adjust panning speed

local mouse_pos = {0, 0}

local resources = {
    wood = 0,
    grain = 2,
    water = 10,
    stone = 10,
    gold = 0,
    tools = 50
}

local stats = {
    population = 1,
    max_population = 10, -- initial limit (people live in the castle)
    happiness = 5 -- base happiness
}


local turn_actions = 1 -- number of remaining actions in this turn

local tree_cutting_mode = false
local hovered_tree = nil
local last_hovered_tree = nil
local tree_animation_time = 0

local build_ui_visible = false
local build_panel = nil
local build_buttons = {}
local build_ui_animation_time = 0
local build_ui_animation_duration = 0.3

local building_placement_mode = false
local selected_building = nil
local hovered_hex = nil
local last_hovered_hex = nil
local building_preview = nil

local building_types = {
    home = {
        models = { "building_home_A_green.fbx", "building_home_A_blue.fbx" },
        cost = { stone = 2, wood = 2, tools = 1 },
        one_time = { population_limit = 1 },
        unlocked = true
    },
    field = {
        models = { "building_grain.fbx" },
        cost = { wood = 1, tools = 1 },
        per_turn = { grain = 1 },
        unlocked = true
    },
    well = {
        models = { "building_well_blue.fbx", "building_well_green.fbx" },
        cost = { stone = 2, wood = 1, tools = 1 },
        per_turn = { water = 1 },
        unlocked = true
    },
    mine = {
        models = { "building_mine_blue.fbx", "building_mine_green.fbx" },
        cost = { wood = 4, stone = 2, tools = 3 },
        per_turn = { stone = 1 }
    },
    lumbermill = {
        models = { "building_lumbermill_blue.fbx", "building_lumbermill_green.fbx" },
        cost = { stone = 1, wood = 1, tools = 1 },
        per_turn = { wood = 1 }
    },
    tavern = {
        models = { "building_tavern_blue.fbx", "building_tavern_green.fbx" },
        cost = { stone = 3, wood = 3, tools = 2 },
        one_time = { happiness = 10 }
    },
    blacksmith = {
        models = { "building_blacksmith_blue.fbx", "building_blacksmith_green.fbx" },
        cost = { stone = 3, wood = 3, tools = 3 },
        per_turn = { tools = 1 }
    },
    windmill = {
        models = { "building_windmill_blue.fbx", "building_windmill_green.fbx" },
        cost = { stone = 3, wood = 2, tools = 4 },
        per_turn = { actions = 1 }
    },
    market = {
        models = { "building_market_blue.fbx", "building_market_green.fbx" },
        cost = { stone = 5, wood = 5, tools = 5 },
    }
}

local function update_ui()
    for res, entity in pairs(resource_texts) do
        entity.gui_text.text = res .. ": " .. resources[res]
    end
    stat_entities[1].gui_text.text = "Population: " .. stats.population .. "/" .. stats.max_population
    stat_entities[2].gui_text.text = "Happiness: " .. stats.happiness
    stat_entities[3].gui_text.text = "Actions: " .. turn_actions
end

local function can_afford(cost)
    for res, amount in pairs(cost or {}) do
        if (resources[res] or 0) < amount then return false end
    end
    return true
end

-- Grid data structure to store hex information
local hex_grid = {}

local tree_models = {
    "trees_A_large.fbx",
    "trees_A_medium.fbx",
    "trees_A_small.fbx",
    "trees_B_large.fbx",
    "trees_B_medium.fbx",
    "trees_B_small.fbx",
    "tree_single_A.fbx",
    "tree_single_B.fbx"
}

local mountain_models = {
    "mountain_A.fbx",
    "mountain_B.fbx",
    "mountain_C.fbx",
    "hill_single_A.fbx",
    "hill_single_B.fbx",
    "hill_single_C.fbx"
}

local water_feature_models = {
    "waterlily_A.fbx",
    "waterlily_B.fbx",
    "waterplant_A.fbx",
    "waterplant_B.fbx",
    "waterplant_C.fbx"
}

local function create_hex(x, z, model, name_prefix)
    local offset_x = (z % 2) * (HEX_SPACING_X / 2)
    local pos_x = x * HEX_SPACING_X + offset_x - center_x
    local pos_z = z * HEX_SPACING_Z - center_z
    local entity = this.world:createEntityEx({
        name = string.format(name_prefix .. "_%d_%d", x, z),
        position = {pos_x, 0, pos_z},
        model_instance = {source = "hex/models/" .. model},
        parent = hex_group
    })
    
    -- Store hex data
    if not hex_grid[z] then hex_grid[z] = {} end
    hex_grid[z][x] = {
        entity = entity,
        x = x,
        z = z,
        pos_x = pos_x,
        pos_z = pos_z,
        type = name_prefix,
        features = {},
        building = nil
    }
    
    return pos_x, pos_z
end

local function create_feature(x, z, pos_x, pos_z, model_list, feature_type, index)
    local model = model_list[math.random(#model_list)]
    local name_suffix = index and string.format("_%d_%d_%d", x, z, index) or string.format("_%d_%d", x, z)
    local entity = this.world:createEntityEx({
        name = feature_type .. name_suffix,
        position = {pos_x, 0, pos_z},
        model_instance = {source = "hex/models/" .. model},
        parent = hex_group
    })
    
    -- Store feature in hex
    local feature = {entity = entity, type = feature_type}
    table.insert(hex_grid[z][x].features, feature)
end

-- Get hex at grid coordinates
local function getHex(x, z)
    if hex_grid[z] and hex_grid[z][x] then
        return hex_grid[z][x]
    end
    return nil
end

local function place_starting_castle()
    -- Place castle at the center of the grid
    local center_hex_x = math.floor(GRID_WIDTH / 2)
    local center_hex_z = math.floor(GRID_HEIGHT / 2)
    
    -- Get the position of the center hex
    local hex = getHex(center_hex_x, center_hex_z)
    if hex then
        -- Place the castle slightly above the hex
        this.world:createEntityEx({
            name = "starting_castle",
            position = {hex.pos_x, 0.0, hex.pos_z},  -- Slightly elevated
            rotation = {0, 0, 0, 1},  -- No rotation
            model_instance = {source = "hex/models/building_castle_blue.fbx"},
            parent = hex_group
        })
        LumixAPI.logInfo("Placed starting castle at hex (" .. center_hex_x .. ", " .. center_hex_z .. ")")
    end
end

local function create_border_hexes(start_x, end_x, start_z, end_z)
    for z = start_z, end_z do
        for x = start_x, end_x do
            create_hex(x, z, "hex_water.fbx", "hex_water")
        end
    end
end

local create_map = function()
    math.randomseed(os.time())
    -- Create a group entity for all hexes
    hex_group = this.world:createEntityEx({name = "hex_grid"})
    
    -- Create a camera to view the scene
    local camera_height = 40
    local camera_distance = 40
    local pitch = -0.8  -- Downward tilt in radians
    local half_pitch = pitch * 0.5
    camera_entity = this.world:createEntityEx({
        name = "main_camera",
        position = {0, camera_height, camera_distance},
        rotation = {math.sin(half_pitch), 0, 0, math.cos(half_pitch)},  -- Quaternion: (x, y, z, w)
        camera = {
            fov = math.pi / 3,  -- 60 degrees in radians
            near = 0.1,
            far = 1000
        }
    })

    -- Create the inner grid with random features
    for z = 0, GRID_HEIGHT - 1 do
        for x = 0, GRID_WIDTH - 1 do
            -- Pre-determine terrain type
            local center_hex_x = math.floor(GRID_WIDTH / 2)
            local center_hex_z = math.floor(GRID_HEIGHT / 2)
            local is_center = (x == center_hex_x and z == center_hex_z)
            local is_water_hex = not is_center and math.random() < WATER_FEATURE_PROBABILITY
            local hex_model = is_water_hex and "hex_water.fbx" or "hex_grass.fbx"
            local hex_name_prefix = is_water_hex and "hex_water" or "hex"
            
            local pos_x, pos_z = create_hex(x, z, hex_model, hex_name_prefix)
            
            -- Skip features on the center hex to keep it empty for the castle
            if is_center then
                -- Do not place features on center hex
            else
                -- Place features based on terrain type
                if is_water_hex then
                    -- Place 8 water features randomly scattered within the hex
                    for i = 1, 8 do
                        -- Generate random position within hex bounds (roughly circular)
                        local angle = math.random() * 2 * math.pi
                        local radius = math.random() * 0.8  -- Keep within ~80% of hex radius
                        local offset_x = radius * math.cos(angle)
                        local offset_z = radius * math.sin(angle)
                        create_feature(x, z, pos_x + offset_x, pos_z + offset_z, water_feature_models, "water", i)
                    end
                else
                    -- Place trees or mountains on grass hexes (mutually exclusive)
                    if math.random() < TREE_PROBABILITY then
                        create_feature(x, z, pos_x, pos_z, tree_models, "tree")
                    elseif math.random() < MOUNTAIN_PROBABILITY then
                        create_feature(x, z, pos_x, pos_z, mountain_models, "mountain")
                    end
                end
            end
        end
    end

    -- Add water border around the grid (2 hexes wide)
    -- Inner border (original border)
    create_border_hexes(-1, GRID_WIDTH, GRID_HEIGHT, GRID_HEIGHT)      -- Top row
    create_border_hexes(-1, GRID_WIDTH, -1, -1)                        -- Bottom row
    create_border_hexes(-1, -1, 0, GRID_HEIGHT - 1)                    -- Left column
    create_border_hexes(GRID_WIDTH, GRID_WIDTH, 0, GRID_HEIGHT - 1)    -- Right column
    
    -- Outer border (additional layer)
    create_border_hexes(-2, GRID_WIDTH + 1, GRID_HEIGHT + 1, GRID_HEIGHT + 1)  -- Top row
    create_border_hexes(-2, GRID_WIDTH + 1, -2, -2)                            -- Bottom row
    create_border_hexes(-2, -2, -1, GRID_HEIGHT)                               -- Left column
    create_border_hexes(GRID_WIDTH + 1, GRID_WIDTH + 1, -1, GRID_HEIGHT)       -- Right column
    
    -- Place starting castle
    place_starting_castle()
end

local function next_turn()
    LumixAPI.logInfo("Next turn started")
    
    -- Production phase
    local industrial_count = 0
    local tavern_count = 0
    for z = 0, GRID_HEIGHT - 1 do
        for x = 0, GRID_WIDTH - 1 do
            local hex = getHex(x, z)
            if hex and hex.building then
                local building_data = building_types[hex.building.type]
                if building_data.per_turn then
                    for res, amount in pairs(building_data.per_turn) do
                        if res == "actions" then
                            turn_actions = turn_actions + amount
                        else
                            resources[res] = resources[res] + amount
                        end
                    end
                end
                -- count for happiness
                if hex.building.type == "mine" or hex.building.type == "lumbermill" then
                    industrial_count = industrial_count + 1
                elseif hex.building.type == "tavern" then
                    tavern_count = tavern_count + 1
                end
            end
        end
    end
    
    -- Consumption phase: consume resources based on population
    local grain_consumed = math.min(stats.population, resources.grain)
    local water_consumed = math.min(stats.population, resources.water)
    
    LumixAPI.logInfo("Consumption: Population " .. stats.population .. " consuming " .. grain_consumed .. " grain and " .. water_consumed .. " water")
    
    resources.grain = resources.grain - grain_consumed
    resources.water = resources.water - water_consumed
    
    -- Population shrink due to insufficient resources
    local missing_resources = stats.population - grain_consumed + stats.population - water_consumed
    if missing_resources > 0 then
        LumixAPI.logInfo("Population shrinking due to insufficient resources: " .. missing_resources .. " units lost")
        stats.population = stats.population - missing_resources
    end
    
    -- Population shrink due to happiness = 0
    if stats.happiness <= 0 then
        LumixAPI.logInfo("Population shrinking due to low happiness: 1 unit lost")
        stats.population = math.max(0, stats.population - 1)
    end
    
    -- Update happiness (reset each turn based on current state)
    -- Base happiness minus population minus industrial buildings (to be implemented)
    local old_happiness = stats.happiness
    stats.happiness = 5 - stats.population - industrial_count + tavern_count * 10
    
    LumixAPI.logInfo("Happiness updated: " .. old_happiness .. " -> " .. stats.happiness)
    
    -- Population growth phase
    local can_grow = stats.happiness > 0 and stats.population < stats.max_population and 
                     resources.grain >= stats.population + 1 and resources.water >= stats.population + 1
    
    if can_grow then
        LumixAPI.logInfo("Population growing: conditions met (happiness > 0, space available, sufficient resources)")
        stats.population = stats.population + 1
    else
        local reasons = {}
        if stats.happiness <= 0 then table.insert(reasons, "happiness <= 0") end
        if stats.population >= stats.max_population then table.insert(reasons, "at max population") end
        if resources.grain < stats.population + 1 then table.insert(reasons, "insufficient grain") end
        if resources.water < stats.population + 1 then table.insert(reasons, "insufficient water") end
        LumixAPI.logInfo("Population not growing: " .. table.concat(reasons, ", "))
    end
    
    -- Compute new number of actions
    local base_actions = stats.population
    turn_actions = base_actions
    if stats.happiness <= 0 then
        turn_actions = math.floor(turn_actions / 2)
        LumixAPI.logInfo("Actions halved due to low happiness: " .. base_actions .. " -> " .. turn_actions)
    else
        LumixAPI.logInfo("Actions set to population: " .. turn_actions)
    end
    
    -- Update UI
    update_ui()
    
    LumixAPI.logInfo("Next turn completed - Population: " .. stats.population .. ", Actions: " .. turn_actions .. ", Resources: grain=" .. resources.grain .. ", water=" .. resources.water)
end

local function create_build_panel(canvas)
    -- Create build panel
    build_panel = this.world:createEntityEx({
        gui_rect = {
            left_relative = 1,
            left_points = 0,  -- start off-screen
            right_relative = 1,
            right_points = 0,
            top_points = 50,
            bottom_relative = 1,
            bottom_points = 0
        },
        gui_image = { color = {0.8, 0.8, 0.8, 0.9} },
        parent = canvas
    })

    -- Get unlocked buildings
    local unlocked_buildings = {}
    for name, building in pairs(building_types) do
        if building.unlocked then
            table.insert(unlocked_buildings, {name = name, data = building})
        end
    end

    -- Create buttons for each unlocked building
    build_buttons = {}
    for i, building in ipairs(unlocked_buildings) do
        local button = this.world:createEntityEx({
            gui_button = {},
            gui_rect = {
                left_points = 10,
                right_points = 290,
                top_points = 10 + (i-1)*60,
                bottom_points = 60 + (i-1)*60,
                bottom_relative = 0
            },
            gui_image = {
                sprite = "ui/button_rectangle_border.spr"
            },
            gui_text = {
                text = building.name,
                font_size = 24,
                color = {0.0, 0.0, 0.0, 1.0},
                font = "ui/font/Kenney Future.ttf",
                horizontal_align = LumixAPI.TextHAlign.CENTER,
                vertical_align = LumixAPI.TextVAlign.MIDDLE
            },
            lua_script = {},
            parent = build_panel
        })
        button.lua_script.scripts:add()
        button.lua_script[1].onButtonClicked = function()
            if can_afford(building.data.cost) then
                selected_building = building.name
                building_placement_mode = true
                tree_cutting_mode = false
                build_ui_visible = false
                build_ui_animation_time = 0
                LumixAPI.logInfo("Selected building: " .. building.name)
            else
                LumixAPI.logInfo("Cannot afford building: " .. building.name)
            end
        end
        table.insert(build_buttons, button)
    end
end

function start()
    -- Enable cursor for interaction
    local gui_system = this.world:getModule("gui"):getSystem()
    gui_system:enableCursor(true)
	
    create_map()

    -- Create HUD canvas
    local canvas = this.world:createEntityEx({
        gui_canvas = {},
        gui_rect = {}
    })

    local top_strip = this.world:createEntityEx({
        gui_rect = {
            bottom_relative = 0,
            bottom_points = 50
        },
        gui_image = { color = {1, 1, 1, 0.1} },
        parent = canvas
    })

    -- Create resource texts
    local resource_order = {"wood", "grain", "water", "stone", "gold", "tools"}
    resource_texts = {}
    for i, res in ipairs(resource_order) do
        local entity = this.world:createEntityEx({
            gui_text = {text = res .. ": " .. resources[res], font_size = 30, color = {0.0, 0.0, 0.0, 1.0}, font = "ui/font/Kenney Future.ttf"},
            gui_rect = {left_points = 10 + (i-1)*200, top_points = 10},
            parent = top_strip
        })
        resource_texts[res] = entity
    end

    -- Create stat texts
    local stat_texts = {
        "Population: " .. stats.population .. "/" .. stats.max_population,
        "Happiness: " .. stats.happiness,
        "Actions: " .. turn_actions
    }
    stat_entities = {}
    for i, text in ipairs(stat_texts) do
        local entity = this.world:createEntityEx({
            gui_text = {text = text, font_size = 30, color = {0.0, 0.0, 0.0, 1.0}, font = "ui/font/Kenney Future.ttf"},
            gui_rect = {left_points = 10 + 6*200 + 150 + (i-1)*300, top_points = 10},
            parent = top_strip
        })
        stat_entities[i] = entity
    end

    -- Create next turn button
    local next_turn_button = this.world:createEntityEx({
        gui_button = {},
        gui_rect = {
            left_relative = 1,
            left_points = -250,
            right_relative = 1,
            right_points = -5,
            top_relative = 1,
            top_points = -75,
            bottom_relative = 1,
            bottom_points = -5
        },
        gui_image = {
            sprite = "ui/button_rectangle_border.spr"
        },
        gui_text = {
            text = "Next Turn",
            font_size = 30,
            color = {0.0, 0.0, 0.0, 1.0},
            font = "ui/font/Kenney Future.ttf",
            horizontal_align = LumixAPI.TextHAlign.CENTER,
            vertical_align = LumixAPI.TextVAlign.MIDDLE
        },
        lua_script = {},
        parent = canvas
    })
    next_turn_button.lua_script.scripts:add()
    next_turn_button.lua_script[1].onButtonClicked = function()
        next_turn()
    end

    -- Create cut trees button
    local cut_trees_button = this.world:createEntityEx({
        gui_button = {},
        gui_rect = {
            left_points = 10,
            right_points = 250,
            right_relative = 0,
            top_relative = 1,
            top_points = -75,
            bottom_relative = 1,
            bottom_points = -5
        },
        gui_image = {
            sprite = "ui/button_rectangle_border.spr"
        },
        gui_text = {
            text = "Cut Trees",
            font_size = 30,
            color = {0.0, 0.0, 0.0, 1.0},
            font = "ui/font/Kenney Future.ttf",
            horizontal_align = LumixAPI.TextHAlign.CENTER,
            vertical_align = LumixAPI.TextVAlign.MIDDLE
        },
        lua_script = {},
        parent = canvas
    })
    cut_trees_button.lua_script.scripts:add()
    cut_trees_button.lua_script[1].onButtonClicked = function()
        tree_cutting_mode = not tree_cutting_mode
        LumixAPI.logInfo("Tree cutting mode: " .. tostring(tree_cutting_mode))
    end

    -- Create build button
    local build_button = this.world:createEntityEx({
        gui_button = {},
        gui_rect = {
            left_points = 260,
            right_points = 500,
            right_relative = 0,
            top_relative = 1,
            top_points = -75,
            bottom_relative = 1,
            bottom_points = -5
        },
        gui_image = {
            sprite = "ui/button_rectangle_border.spr"
        },
        gui_text = {
            text = "Build",
            font_size = 30,
            color = {0.0, 0.0, 0.0, 1.0},
            font = "ui/font/Kenney Future.ttf",
            horizontal_align = LumixAPI.TextHAlign.CENTER,
            vertical_align = LumixAPI.TextVAlign.MIDDLE
        },
        lua_script = {},
        parent = canvas
    })
    build_button.lua_script.scripts:add()
    build_button.lua_script[1].onButtonClicked = function()
        build_ui_visible = not build_ui_visible
        build_ui_animation_time = 0
        if build_ui_visible and not build_panel then
            create_build_panel(canvas)
        end
    end

    update_ui()
end

-- Convert world position to hex coordinates
local function worldToHex(wx, wz)
    -- Convert world coordinates back to hex grid coordinates
    local local_x = wx + center_x
    local local_z = wz + center_z
    
    -- Find the closest hex center
    local z = math.floor(local_z / HEX_SPACING_Z + 0.5)
    local x_offset = (z % 2) * (HEX_SPACING_X / 2)
    local x = math.floor((local_x - x_offset) / HEX_SPACING_X + 0.5)
    
    -- Clamp to grid bounds
    x = math.max(0, math.min(GRID_WIDTH - 1, x))
    z = math.max(0, math.min(GRID_HEIGHT - 1, z))
    
    return x, z
end

function onInputEvent(event)
    if event.type == "mouse_wheel" then
        zoom_wheel = zoom_wheel - event.y * MOUSE_WHEEL_ZOOM_MULTIPLIER
    elseif event.type == "axis" and event.device.type == "mouse" then
        mouse_pos[1] = event.x_abs
        mouse_pos[2] = event.y_abs
    elseif event.type == "button" then
        if event.device.type == "keyboard" then
            -- Handle camera movement keys
            if event.key_id == LumixAPI.Keycode.W then
                move_forward = event.down and 1 or 0
            elseif event.key_id == LumixAPI.Keycode.S then
                move_back = event.down and 1 or 0
            elseif event.key_id == LumixAPI.Keycode.A then
                move_left = event.down and 1 or 0
            elseif event.key_id == LumixAPI.Keycode.D then
                move_right = event.down and 1 or 0
            elseif event.key_id == LumixAPI.Keycode.Q then
                zoom_in = event.down and 1 or 0
            elseif event.key_id == LumixAPI.Keycode.E then
                zoom_out = event.down and 1 or 0
            end
        elseif event.device.type == "mouse" then
            if event.key_id == 0 and event.down then
                -- Left mouse button click - select hex
                if camera_entity and camera_entity.camera then
                    local ray = camera_entity.camera:getRay(mouse_pos)
                    
                    -- Intersect ray with ground plane (y = 0)
                    if ray.dir[2] ~= 0 then
                        local t = (0 - ray.origin[2]) / ray.dir[2]
                        if t >= 0 then
                            local hit_pos = {
                                ray.origin[1] + ray.dir[1] * t,
                                0,
                                ray.origin[3] + ray.dir[3] * t
                            }
                            
                            local hex_x, hex_z = worldToHex(hit_pos[1], hit_pos[3])
                            local hex = getHex(hex_x, hex_z)
                            
                            -- Handle tree cutting
                            if tree_cutting_mode and hovered_tree then
                                local current_model = hovered_tree.model_instance.source
                                local new_model
                                if string.find(current_model, "trees_A") then
                                    new_model = "trees_A_cut.fbx"
                                elseif string.find(current_model, "trees_B") then
                                    new_model = "trees_B_cut.fbx"
                                elseif string.find(current_model, "tree_single_A") then
                                    new_model = "tree_single_A_cut.fbx"
                                elseif string.find(current_model, "tree_single_B") then
                                    new_model = "tree_single_B_cut.fbx"
                                else
                                    new_model = "trees_A_cut.fbx" -- default
                                end
                                hovered_tree.model_instance.source = "hex/models/" .. new_model
                                resources.wood = resources.wood + 4
                                turn_actions = turn_actions - 1
                                update_ui()
                                -- Mark as cut
                                for _, feature in ipairs(hex.features) do
                                    if feature.entity == hovered_tree then
                                        feature.type = "cut_tree"
                                        break
                                    end
                                end
                                hovered_tree = nil
                                tree_cutting_mode = false
                            elseif building_placement_mode and hovered_hex and hovered_hex.type == "hex" and not hovered_hex.building then
                                -- place building
                                local building_data = building_types[selected_building]
                                if can_afford(building_data.cost) then
                                    local model = building_data.models[math.random(#building_data.models)]
                                    local entity = this.world:createEntityEx({
                                        name = selected_building .. "_" .. hovered_hex.x .. "_" .. hovered_hex.z,
                                        position = {hovered_hex.pos_x, 0, hovered_hex.pos_z},
                                        model_instance = {source = "hex/models/" .. model},
                                        parent = hex_group
                                    })
                                    -- deduct resources
                                    for res, amount in pairs(building_data.cost) do
                                        resources[res] = resources[res] - amount
                                    end
                                    -- remove existing features
                                    for _, feature in ipairs(hovered_hex.features) do
                                        feature.entity:destroy()
                                    end
                                    hovered_hex.features = {}
                                    -- add to hex
                                    hovered_hex.building = {type = selected_building, entity = entity}
                                    -- apply one_time effects
                                    if building_data.one_time then
                                        for effect, value in pairs(building_data.one_time) do
                                            if effect == "population_limit" then
                                                stats.max_population = stats.max_population + value
                                            elseif effect == "happiness" then
                                                stats.happiness = stats.happiness + value
                                            end
                                        end
                                    end
                                    -- consume action
                                    turn_actions = turn_actions - 1
                                    -- exit mode
                                    building_placement_mode = false
                                    if building_preview then building_preview:destroy() building_preview = nil end
                                    update_ui()
                                    LumixAPI.logInfo("Placed building: " .. selected_building)
                                    selected_building = nil
                                else
                                    LumixAPI.logInfo("Cannot afford building")
                                end
                            end
                        end
                    end
                end
            elseif event.key_id == 1 then
                -- Right mouse button - start/stop panning
                mouse_panning = event.down
                if event.down then
                    last_mouse_x = mouse_pos[1]
                    last_mouse_y = mouse_pos[2]
                    -- Hide cursor while panning
                    local gui_system = this.world.gui:getSystem()
                    gui_system:enableCursor(false)
                else
                    -- Show cursor when panning stops
                    local gui_system = this.world.gui:getSystem()
                    gui_system:enableCursor(true)
                end
            end
        end
    end
end

function update(dt)
    if not camera_entity then return end
    
    local move_dir = {0, 0, 0}
    local zoom = 0
    
    -- Camera movement
    move_dir[1] = move_dir[1] + move_right - move_left
    move_dir[3] = move_dir[3] + move_back - move_forward
    
    -- Zoom
    zoom = zoom + zoom_out - zoom_in
    zoom = zoom + zoom_wheel
    
    -- Normalize movement direction
    local move_length = math.sqrt(move_dir[1] * move_dir[1] + move_dir[3] * move_dir[3])
    if move_length > 0 then
        move_dir[1] = move_dir[1] / move_length
        move_dir[3] = move_dir[3] / move_length
    end
    
    -- Apply camera movement
    local pos = camera_entity.position
    pos[1] = pos[1] + move_dir[1] * camera_speed * dt
    pos[3] = pos[3] + move_dir[3] * camera_speed * dt
    
    -- Mouse panning
    if mouse_panning then
        local delta_x = mouse_pos[1] - last_mouse_x
        local delta_y = mouse_pos[2] - last_mouse_y
        
        -- Apply mouse movement to camera position (inverted Y for natural feel)
        pos[1] = pos[1] - delta_x * pan_sensitivity
        pos[3] = pos[3] - delta_y * pan_sensitivity
        
        -- Update last mouse position
        last_mouse_x = mouse_pos[1]
        last_mouse_y = mouse_pos[2]
    end
    
    -- Clamp camera position to boundaries
    pos[1] = math.max(camera_min_x, math.min(camera_max_x, pos[1]))
    pos[3] = math.max(camera_min_z, math.min(camera_max_z, pos[3]))
    
    -- Apply zoom (change height)
    local height = pos[2] + zoom * camera_zoom_speed * dt
    height = math.max(camera_min_height, math.min(camera_max_height, height))
    pos[2] = height
    
    camera_entity.position = pos
    
    -- Handle tree cutting mode hover
    if tree_cutting_mode and camera_entity and camera_entity.camera then
        local ray = camera_entity.camera:getRay(mouse_pos)
        if ray.dir[2] ~= 0 then
            local t = (0 - ray.origin[2]) / ray.dir[2]
            if t >= 0 then
                local hit_pos = {
                    ray.origin[1] + ray.dir[1] * t,
                    0,
                    ray.origin[3] + ray.dir[3] * t
                }
                local mouse_hex_x, mouse_hex_z = worldToHex(hit_pos[1], hit_pos[3])
                local hex = getHex(mouse_hex_x, mouse_hex_z)
                hovered_tree = nil
                if hex and hex.features then
                    for _, feature in ipairs(hex.features) do
                        if feature.type == "tree" then
                            hovered_tree = feature.entity
                            break
                        end
                    end
                end
            end
        end
    else
        hovered_tree = nil
    end
    
    -- Reset animation if hovered tree changed
    if hovered_tree ~= last_hovered_tree then
        if last_hovered_tree then
            last_hovered_tree.position = {last_hovered_tree.position[1], 0, last_hovered_tree.position[3]}
        end
        last_hovered_tree = hovered_tree
        tree_animation_time = 0
    end
    
    -- Animate hovered tree
    if hovered_tree then
        tree_animation_time = tree_animation_time + dt * 2.0
        hovered_tree.position = {hovered_tree.position[1], math.sin(tree_animation_time) * 0.3, hovered_tree.position[3]}
    end

    -- Animate build UI panel
    if build_panel then
        build_ui_animation_time = build_ui_animation_time + dt
        local t = math.min(build_ui_animation_time / build_ui_animation_duration, 1)
        local target_left = build_ui_visible and -300 or 0
        local current_left = build_panel.gui_rect.left_points
        build_panel.gui_rect.left_points = current_left + (target_left - current_left) * t * 4  -- *4 for faster animation
        if not build_ui_visible and t >= 1 then
            -- Destroy panel when fully hidden
            build_panel:destroy()
            build_panel = nil
            build_buttons = {}
        end
    end

    -- Handle building placement mode hover
    if building_placement_mode and camera_entity and camera_entity.camera then
        local ray = camera_entity.camera:getRay(mouse_pos)
        if ray.dir[2] ~= 0 then
            local t = (0 - ray.origin[2]) / ray.dir[2]
            if t >= 0 then
                local hit_pos = {
                    ray.origin[1] + ray.dir[1] * t,
                    0,
                    ray.origin[3] + ray.dir[3] * t
                }
                local hex_x, hex_z = worldToHex(hit_pos[1], hit_pos[3])
                local hex = getHex(hex_x, hex_z)
                hovered_hex = hex
                if hex and hex.type == "hex" and not hex.building then
                    -- create preview
                    if not building_preview or last_hovered_hex ~= hex then
                        if building_preview then building_preview:destroy() end
                        local model = building_types[selected_building].models[math.random(#building_types[selected_building].models)]
                        building_preview = this.world:createEntityEx({
                            name = "building_preview",
                            position = {hex.pos_x, 0, hex.pos_z},
                            model_instance = {source = "hex/models/" .. model},
                            parent = hex_group
                        })
                    end
                else
                    if building_preview then building_preview:destroy() building_preview = nil end
                end
                last_hovered_hex = hovered_hex
            end
        end
    else
        if building_preview then building_preview:destroy() building_preview = nil end
        hovered_hex = nil
        last_hovered_hex = nil
    end

    -- Reset wheel zoom
    zoom_wheel = 0
end

