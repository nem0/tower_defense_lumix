-- tower_defense.lua
-- Simple Tower Defense Game Script for Lumix Engine

-- TODO
-- upgrading towers
-- UI
-- fix river crossings
-- particles

local GRID_SIZE = 20  -- Size of the grid, tweakable for larger/smaller maps
local TILE_SPACING = 1
local BULLET_SCALE = 2.0  -- Adjust bullet size
local PROJECTILE_OFFSET_Y = 1.0  -- Height above terrain for projectiles
local SPAWN_INTERVAL = 2.0  -- Seconds between enemy spawns
local AIM_TOLERANCE = 0.1  -- Radians tolerance for aiming before firing
local TREE_OFFSET_Y = 0.15  -- Adjust this to position trees above terrain
local TREE_PROBABILITY = 0.7 -- Chance (0..1) to populate a non-path tile with trees
local TREE_JITTER = 0.4 -- Max random additional offset as fraction of TILE_SPACING
local TREES_PER_TILE = 8 -- Number of tree models to place on a populated tile
local TOWER_OFFSET_Y = 0.15  -- Adjust this to position towers above terrain
local WEAPON_OFFSET_Y = 0.75  -- Adjust this to position weapons above towers

local spawn_timer = 0
local current_wave = 1
local enemies_spawned_in_wave = 0
local wave_active = false
local wave_delay_timer = 0
local wave_delay = 5.0  -- Configurable delay between waves in seconds
local start_wave_early = false
local enemies = {}
local towers = {}
local projectiles = {}
local enemies_data = {}
local towers_data = {}
local projectiles_data = {}
local end_pos = {15, 0, 0}
local grid_passable = {}
local path_tiles = {}
local river_tiles = {}
local map_start = {}
local map_end = {}
local trees = {}
camera = Lumix.Entity.NULL -- set from property grid
local placeholder_tower = nil
local mouse_x = 0.5
local mouse_y = 0.5
local path_set = {}
local river_set = {}
local left_click = false
selected_type = 1
old_selected_type = 1
local score = 400
local score_text = nil
local wave_text = nil
local pulsate_time = 0
local tower_types = {
    {
        model = "models/tower-round-build-c.fbx",
        weapon = "models/weapon-cannon.fbx",
        range = 10,
        damage = 20,
        fireRate = 1,
        ammo = "models/weapon-ammo-cannonball.fbx",
        speed = 5,
        scale = 1.0,
        rotationSpeed = 1.0,
        cost = 100
    },
    {
        model = "models/tower-round-build-a.fbx",
        weapon = "models/weapon-turret.fbx",
        range = 12,
        damage = 25,
        fireRate = 0.8,
        ammo = "models/weapon-ammo-bullet.fbx",
        speed = 8,
        scale = 1.0,
        rotationSpeed = 2.0,
        cost = 150
    },
    {
        model = "models/tower-round-build-b.fbx",
        weapon = "models/weapon-catapult.fbx",
        range = 8,
        damage = 30,
        fireRate = 0.5,
        ammo = "models/weapon-ammo-boulder.fbx",
        speed = 4,
        scale = 1.0,
        rotationSpeed = 0.5,
        cost = 200
    },
    {
        model = "models/tower-square-build-a.fbx",
        weapon = "models/weapon-ballista.fbx",
        range = 11,
        damage = 22,
        fireRate = 1.1,
        ammo = "models/weapon-ammo-arrow.fbx",
        speed = 6,
        scale = 1.0,
        rotationSpeed = 1.5,
        cost = 250
    }
}
local enemy_types = {
    {
        model = "models/enemy-ufo-a.fbx",
        speed = 2.0,
        hp = 100,
        scale = 0.5
    },
    {
        model = "models/enemy-ufo-b.fbx",
        speed = 2.5,
        hp = 80,
        scale = 0.5
    },
    {
        model = "models/enemy-ufo-c.fbx",
        speed = 1.5,
        hp = 150,
        scale = 0.5
    },
    {
        model = "models/enemy-ufo-d.fbx",
        speed = 2.2,
        hp = 120,
        scale = 0.5
    }
}
local waves = {
    { count = 5, enemy_types = {1}, interval = 2.0 },  -- Wave 1: 5 basic enemies
    { count = 8, enemy_types = {1, 2}, interval = 1.8 },  -- Wave 2: 8 enemies, mix of types 1 and 2
    { count = 10, enemy_types = {1, 2, 3}, interval = 1.6 },  -- Wave 3: 10 enemies, types 1-3
    { count = 12, enemy_types = {2, 3, 4}, interval = 1.4 },  -- Wave 4: 12 enemies, tougher types
    { count = 15, enemy_types = {3, 4}, interval = 1.2 },  -- Wave 5: 15 enemies, mostly tough
    { count = 20, enemy_types = {4}, interval = 1.0 }   -- Wave 6: 20 toughest enemies
}
-- Helper functions
function distance(a, b)
    return math.sqrt((a[1] - b[1])^2 + (a[2] - b[2])^2 + (a[3] - b[3])^2)
end

function normalize(v)
    local len = math.sqrt(v[1]^2 + v[2]^2 + v[3]^2)
    return {v[1] / len, v[2] / len, v[3] / len}
end

function lerp_angle(current, target, max_delta)
    local diff = target - current
    diff = ((diff + math.pi) % (2 * math.pi)) - math.pi
    if math.abs(diff) < max_delta then
        return target
    else
        return current + (diff > 0 and 1 or -1) * max_delta
    end
end

function get_dir(a, b)
    if b.x > a.x then return 0  -- right (x+)
    elseif b.x < a.x then return 2  -- left (x-)
    elseif b.z > a.z then return 1  -- down (z+)
    else return 3  -- up (z-)
    end
end

local function find_path(start, goal)
    local queue = {}
    local visited = {}
    local parent = {}
    for x = 1, GRID_SIZE do
        visited[x] = {}
        for z = 1, GRID_SIZE do
            visited[x][z] = false
        end
    end
    queue[1] = start
    visited[start.x][start.z] = true
    parent[start.x .. "," .. start.z] = nil
    local found = false
    while #queue > 0 do
        local current = table.remove(queue, 1)
        if current.x == goal.x and current.z == goal.z then
            found = true
            break
        end
        local dirs = {{0, 1}, {0, -1}, {1, 0}, {-1, 0}}
        for _, d in ipairs(dirs) do
            local nx = current.x + d[1]
            local nz = current.z + d[2]
            if nx >= 1 and nx <= GRID_SIZE and nz >= 1 and nz <= GRID_SIZE and grid_passable[nx][nz] and not visited[nx][nz] then
                visited[nx][nz] = true
                queue[#queue + 1] = {x = nx, z = nz}
                parent[nx .. "," .. nz] = current
            end
        end
    end
    if not found then return nil end
    local path = {}
    local current = goal
    while current do
        table.insert(path, 1, current)
        local key = current.x .. "," .. current.z
        current = parent[key]
    end
    return path
end

local function generateMap()
    -- Reset passable
    for x = 1, GRID_SIZE do
        for z = 1, GRID_SIZE do
            grid_passable[x][z] = true
        end
    end

    -- Add random obstacles to create more turns in the path
    for x = 1, GRID_SIZE do
        for z = 1, GRID_SIZE do
            if math.random() < 0.3 then  -- 30% chance to be impassable
                grid_passable[x][z] = false
            end
        end
    end

    -- Random start and end on edges
    map_start = {x = 1, z = math.random(1, GRID_SIZE)}
    map_end = {x = GRID_SIZE, z = math.random(1, GRID_SIZE)}

    -- Ensure start and end passable
    grid_passable[map_start.x][map_start.z] = true
    grid_passable[map_end.x][map_end.z] = true

    -- Find path
    local path = find_path(map_start, map_end)
    if not path then
        -- Retry
        return generateMap()
    end

    -- Set path_tiles
    path_tiles = path

    -- Identify corner tiles
    local corner_set = {}
    for i = 2, #path_tiles - 1 do
        local dir1 = get_dir(path_tiles[i-1], path_tiles[i])
        local dir2 = get_dir(path_tiles[i], path_tiles[i+1])
        if dir1 ~= dir2 then
            corner_set[path_tiles[i].x .. "," .. path_tiles[i].z] = true
        end
    end

    local temp_path_set = {}
    for _, tile in ipairs(path_tiles) do
        temp_path_set[tile.x .. "," .. tile.z] = true
    end

    -- Generate river
    local river_start = {x = math.random(1, GRID_SIZE), z = 1}
    local river_end = {x = math.random(1, GRID_SIZE), z = GRID_SIZE}
    -- Ensure not same as enemy start/end
    while (river_start.x == map_start.x and river_start.z == map_start.z) or (river_start.x == map_end.x and river_start.z == map_end.z) do
        river_start.x = math.random(1, GRID_SIZE)
    end
    while (river_end.x == map_start.x and river_end.z == map_start.z) or (river_end.x == map_end.x and river_end.z == map_end.z) do
        river_end.x = math.random(1, GRID_SIZE)
    end
    local river_path = find_path(river_start, river_end)
    if river_path then
        river_tiles = river_path
        local river_set = {}
        for _, tile in ipairs(river_tiles) do
            river_set[tile.x .. "," .. tile.z] = true
        end
        local crossings = 0
        local has_corner_crossing = false
        for _, tile in ipairs(path_tiles) do
            if river_set[tile.x .. "," .. tile.z] then
                crossings = crossings + 1
                if corner_set[tile.x .. "," .. tile.z] then
                    has_corner_crossing = true
                end
            end
        end
        if crossings > 1 or has_corner_crossing then
            return generateMap()
        end
    end
end

function start()
    local gui = this.world:getModule("gui")
    if gui then
        gui:getSystem():enableCursor(true)
    end

    -- Create UI canvas
    local canvas = this.world:createEntityEx({
        gui_canvas = {},
        gui_rect = {}
    })

    -- Create score text
    score_text = this.world:createEntityEx({
        gui_text = {text = "Score: 0", font_size = 60},
        gui_rect = {left_points = 10, top_points = 10}
    })
    score_text.parent = canvas
    score_text.gui_text.font = "ui/font/Kenney Future.ttf"

    -- Create wave text
    wave_text = this.world:createEntityEx({
        gui_text = {text = "Wave: 1", font_size = 60, horizontal_align = LumixAPI.TextHAlign.RIGHT},
        gui_rect = {left_relative = 1, left_points = -320, right_relative = 1, right_points = -10, top_relative = 0, top_points = 10}
    })
    wave_text.parent = canvas
    wave_text.gui_text.font = "ui/font/Kenney Future.ttf"

    -- Create start wave early button
    local start_wave_button = this.world:createEntityEx({
        gui_button = {},
        gui_rect = {
            left_points = 10,
            right_points = 40,
            right_relative = 0,
            top_relative = 1,
            top_points = -30,
            bottom_relative = 1,
            bottom_points = 0
        },
        gui_image = {
            sprite = "ui/button_rectangle_border.spr"
        },
        gui_text = {
            text = "Start Wave Early",
            font_size = 30,
            font = "ui/font/Kenney Future.ttf"
        },
        lua_script = {}
    })
    start_wave_button.parent = canvas
    start_wave_button.lua_script.scripts:add()
    start_wave_button.lua_script[1].onButtonClicked = function()
        start_wave_early = true
        this.world:getModule("audio"):play(this, "ui/Sounds/click-a.ogg", false)
    end

    -- Create tower selection buttons
    local button_size = 100
    local spacing = 10
    local total_width = #tower_types * button_size + (#tower_types - 1) * spacing
    for i = 1, #tower_types do
        local idx = i
        local button = this.world:createEntityEx({
            gui_button = {},
            gui_rect = {
                left_relative = 0.5,
                left_points = -total_width / 2 + (idx - 1) * (button_size + spacing),
                right_relative = 0.5,
                right_points = -total_width / 2 + (idx - 1) * (button_size + spacing) + button_size,
                top_relative = 1,
                top_points = -button_size,
                bottom_relative = 1,
                bottom_points = 0,
            },
            gui_image = {
                sprite = "ui/button_rectangle_border.spr"
            },
            gui_text = {
                text = tostring(idx),
                font_size = 20,
                font = "ui/font/Kenney Future.ttf"
            },
            lua_script = {}
        })
        button.parent = canvas
        button.lua_script.scripts:add()
        button.lua_script[1].onButtonClicked = function()
            selected_type = idx
            this.world:getModule("audio"):play(this, "ui/Sounds/switch-a.ogg", false)
            -- recreate placeholder with new model
            local pos = {0, -100, 0}
            if placeholder_tower then
                pos = placeholder_tower.position
                placeholder_tower:destroy()
            end
            placeholder_tower = this.world:createEntityEx({
                position = pos,
                scale = {0.8, 0.8, 0.8},
                model_instance = {source = tower_types[selected_type].model}
            })
            old_selected_type = selected_type
        end

        local weapon_image = this.world:createEntityEx({
            gui_image = {
                sprite = "ui/" .. string.match(tower_types[idx].weapon, "models/(weapon%-%w+)%.fbx") .. ".spr"
            },
            gui_rect = {
                left_relative = 0.5,
                left_points = -35,
                right_relative = 0.5,
                right_points = 35,
                top_relative = 0.5,
                top_points = -35,
                bottom_relative = 0.5,
                bottom_points = 35
            }
        })
        weapon_image.parent = button
    end
    
    -- Initialize passable grid
    for x = 1, GRID_SIZE do
        grid_passable[x] = {}
        for z = 1, GRID_SIZE do
            grid_passable[x][z] = true
        end
    end

    -- Generate random map
    generateMap()

    -- Set path and river sets for placement check
    path_set = {}
    for _, tile in ipairs(path_tiles) do
        path_set[tile.x .. "," .. tile.z] = true
    end
    river_set = {}
    for _, tile in ipairs(river_tiles) do
        river_set[tile.x .. "," .. tile.z] = true
    end

    -- Compute path models and rotations
    local path_models = {}
    local path_rotations = {}
    for i, tile in ipairs(path_tiles) do
        local dir
        if i == 1 then
            dir = get_dir(path_tiles[1], path_tiles[2])
            path_models[i] = "models/tile-straight.fbx"
        elseif i == #path_tiles then
            dir = get_dir(path_tiles[#path_tiles-1], path_tiles[#path_tiles])
            path_models[i] = "models/tile-straight.fbx"
        else
            local dir1 = get_dir(path_tiles[i-1], path_tiles[i])
            local dir2 = get_dir(path_tiles[i], path_tiles[i+1])
            if dir1 == dir2 then
                dir = dir1
                path_models[i] = "models/tile-straight.fbx"
            else
                local diff = (dir2 - dir1 + 4) % 4
                if diff == 1 then
                    dir = (dir2 + 1) % 4
                elseif diff == 3 then
                    dir = dir2
                else
                    dir = dir2
                end
                path_models[i] = "models/tile-corner-round.fbx"
            end
        end
        -- set rotation
        local theta
        if dir == 0 then theta = math.pi / 2
        elseif dir == 1 then theta = 0
        elseif dir == 2 then theta = -math.pi / 2
        else theta = math.pi
        end
        local half = theta / 2
        path_rotations[i] = {0, math.sin(half), 0, math.cos(half)}
    end

    -- Compute river models and rotations
    local river_models = {}
    local river_rotations = {}
    for i, tile in ipairs(river_tiles) do
        local dir
        if i == 1 then
            dir = get_dir(river_tiles[1], river_tiles[2])
            river_models[i] = "models/tile-river-straight.fbx"
        elseif i == #river_tiles then
            dir = get_dir(river_tiles[#river_tiles-1], river_tiles[#river_tiles])
            river_models[i] = "models/tile-river-straight.fbx"
        else
            local dir1 = get_dir(river_tiles[i-1], river_tiles[i])
            local dir2 = get_dir(river_tiles[i], river_tiles[i+1])
            if dir1 == dir2 then
                dir = dir1
                river_models[i] = "models/tile-river-straight.fbx"
            else
                local diff = (dir2 - dir1 + 4) % 4
                if diff == 1 then
                    dir = (dir2 + 1) % 4
                elseif diff == 3 then
                    dir = dir2
                else
                    dir = dir2
                end
                river_models[i] = "models/tile-river-corner.fbx"
            end
        end
        -- set rotation
        local theta
        if dir == 0 then theta = math.pi / 2
        elseif dir == 1 then theta = 0
        elseif dir == 2 then theta = -math.pi / 2
        else theta = math.pi
        end
        local half = theta / 2
        river_rotations[i] = {0, math.sin(half), 0, math.cos(half)}
    end

    path_index = {}
    for i, tile in ipairs(path_tiles) do
        path_index[tile.x .. "," .. tile.z] = i
    end

    river_index = {}
    for i, tile in ipairs(river_tiles) do
        river_index[tile.x .. "," .. tile.z] = i
    end

    path_set = {}
    for _, tile in ipairs(path_tiles) do
        path_set[tile.x .. "," .. tile.z] = true
    end

    river_set = {}
    for _, tile in ipairs(river_tiles) do
        river_set[tile.x .. "," .. tile.z] = true
    end

    -- Set river tiles non-passable
    for _, tile in ipairs(river_tiles) do
        grid_passable[tile.x][tile.z] = false
    end
    -- Bridges are passable
    for _, tile in ipairs(path_tiles) do
        if path_set[tile.x .. "," .. tile.z] and river_set[tile.x .. "," .. tile.z] then
            grid_passable[tile.x][tile.z] = true
        end
    end

    -- Create grid map
    for x = 0, GRID_SIZE + 1 do
        for z = 0, GRID_SIZE + 1 do
            local pos = {(x - GRID_SIZE / 2) * TILE_SPACING, 0, (z - GRID_SIZE / 2) * TILE_SPACING}
            local model = "models/tile-hill.fbx"
            local rot = nil
            if x >= 1 and x <= GRID_SIZE and z >= 1 and z <= GRID_SIZE then
                if x == map_start.x and z == map_start.z then
                    model = "models/tile-spawn.fbx"
                elseif x == map_end.x and z == map_end.z then
                    model = "models/tile-spawn-end.fbx"
                elseif path_set[x .. "," .. z] and river_set[x .. "," .. z] then
                    model = "models/tile-river-bridge.fbx"
                    rot = river_rotations[river_index[x .. "," .. z]]
                elseif river_set[x .. "," .. z] then
                    local idx = river_index[x .. "," .. z]
                    model = river_models[idx]
                    rot = river_rotations[idx]
                elseif path_set[x .. "," .. z] then
                    local idx = path_index[x .. "," .. z]
                    model = path_models[idx]
                    rot = path_rotations[idx]
                else
                    model = "models/tile.fbx"
                end
            end
            local entity_params = {
                position = pos,
                model_instance = {source = model}
            }
            if rot then
                entity_params.rotation = rot
            end
            this.world:createEntityEx(entity_params)
        end
    end

    -- Fill all non-path, non-river tiles with four trees each at scale 0.5
    local tree_models = {
        "models/detail-tree.fbx",
        "models/detail-tree-large.fbx",
    }
    -- Offsets within a tile to place 4 models (corners)
    local half_offset = 0.25 * TILE_SPACING
    local offsets = {
        {-half_offset, -half_offset},
        {-half_offset, half_offset},
        {half_offset, -half_offset},
        {half_offset, half_offset},
    }
    for x = 1, GRID_SIZE do
        for z = 1, GRID_SIZE do
            if not path_set[x .. "," .. z] and not river_set[x .. "," .. z] then
                -- Only populate this tile with trees based on probability
                if math.random() < TREE_PROBABILITY then
                    if not trees[x] then trees[x] = {} end
                    if not trees[x][z] then trees[x][z] = {} end
                    local center_x = (x - GRID_SIZE / 2) * TILE_SPACING
                    local center_z = (z - GRID_SIZE / 2) * TILE_SPACING
                    -- Place `TREES_PER_TILE` instances: uniform random distribution within the tile
                    for i = 1, TREES_PER_TILE do
                        local base_off_x = (math.random() * 2 - 1) * half_offset
                        local base_off_z = (math.random() * 2 - 1) * half_offset
                        local jitter_x = (math.random() * 2 - 1) * TREE_JITTER * TILE_SPACING
                        local jitter_z = (math.random() * 2 - 1) * TREE_JITTER * TILE_SPACING
                        local pos = {center_x + base_off_x + jitter_x, TREE_OFFSET_Y, center_z + base_off_z + jitter_z}
                        local tree = this.world:createEntityEx({
                            position = pos,
                            scale = {0.7, 0.7, 0.7},
                            model_instance = {source = tree_models[math.random(1, #tree_models)]}
                        })
                        table.insert(trees[x][z], tree)
                    end
                end
            end
        end
    end

    -- Path is already found in generateMap
    local path = path_tiles
    if not path then
        return
    end

    -- placement marker will be created when user toggles placement mode
    -- Create placeholder tower
    placeholder_tower = this.world:createEntityEx({
        position = {0, -100, 0},
        scale = {0.8, 0.8, 0.8},
        model_instance = {source = tower_types[selected_type].model}
    })

    -- Start the first wave
    wave_active = true
end

function spawnEnemy(pos, path, type_index, wave_num)
    local enemy_type = enemy_types[type_index]
    local enemy = this.world:createEntityEx({
        position = pos,
        scale = {enemy_type.scale, enemy_type.scale, enemy_type.scale},
        model_instance = {source = enemy_type.model}
    })
    enemies_data[enemy] = {health = enemy_type.hp, speed = enemy_type.speed, path = path, current_index = 1, wave = wave_num, type = type_index}
    table.insert(enemies, enemy)
end

function placeTower(x, z, type_index)
    local tower_type = tower_types[type_index]
    if score < tower_type.cost then
        return false
    end
    score = score - tower_type.cost

    -- Remove trees in this tile
    if trees[x] and trees[x][z] then
        for _, tree in ipairs(trees[x][z]) do
            tree:destroy()
        end
        trees[x][z] = nil
    end
    local pos = {(x - GRID_SIZE / 2) * TILE_SPACING, TOWER_OFFSET_Y, (z - GRID_SIZE / 2) * TILE_SPACING}
    local tower = this.world:createEntityEx({
        position = pos,
        model_instance = {source = tower_type.model}
    })
    -- Place weapon on top of tower
    local weapon_pos = {(x - GRID_SIZE / 2) * TILE_SPACING, TOWER_OFFSET_Y + WEAPON_OFFSET_Y, (z - GRID_SIZE / 2) * TILE_SPACING}
    local weapon = this.world:createEntityEx({
        position = weapon_pos,
        model_instance = {source = tower_type.weapon}
    })
    towers_data[tower] = {range = tower_type.range, damage = tower_type.damage, fireRate = tower_type.fireRate, lastShot = 0, ammo = tower_type.ammo, speed = tower_type.speed, scale = tower_type.scale, weapon = weapon, rotationSpeed = tower_type.rotationSpeed, current_angle = 0}
    table.insert(towers, tower)
    this.world:getModule("audio"):play(this, "ui/Sounds/switch-a.ogg", false)
    return true
end

function spawnProjectile(pos, target, damage, ammo_model, speed, scale)
    local dir = normalize({target.position[1] - pos[1], 0, target.position[3] - pos[3]})
    local angle = math.atan2(dir[1], dir[3])
    local half_angle = angle / 2
    local proj = this.world:createEntityEx({
        position = {pos[1], pos[2] + PROJECTILE_OFFSET_Y, pos[3]},
        rotation = {0, math.sin(half_angle), 0, math.cos(half_angle)},
        scale = {scale, scale, scale},
        model_instance = {source = ammo_model}
    })
    projectiles_data[proj] = {target = target, damage = damage, speed = speed}
    table.insert(projectiles, proj)
end

function hasEnemiesFromWave(wave_num)
    for _, enemy in ipairs(enemies) do
        local data = enemies_data[enemy]
        if data and data.wave == wave_num then
            return true
        end
    end
    return false
end

function update(dt)
    if not placeholder_tower then
        placeholder_tower = this.world:createEntityEx({
            position = {0, -100, 0},
            scale = {0.8, 0.8, 0.8},
            model_instance = {source = tower_types[selected_type].model}
        })
    end

    -- Spawn enemies in waves
    if wave_active then
        spawn_timer = spawn_timer + dt
        local wave = waves[current_wave]
        if spawn_timer >= wave.interval and enemies_spawned_in_wave < wave.count and map_start.x and path_tiles then
            local start_pos = {(map_start.x - GRID_SIZE / 2) * TILE_SPACING, 0, (map_start.z - GRID_SIZE / 2) * TILE_SPACING}
            local type_index = wave.enemy_types[math.random(1, #wave.enemy_types)]
            spawnEnemy(start_pos, path_tiles, type_index, current_wave)
            enemies_spawned_in_wave = enemies_spawned_in_wave + 1
            spawn_timer = 0
        elseif enemies_spawned_in_wave >= wave.count then
            -- Wave spawning complete, now wait for all enemies to be defeated
            wave_active = false
        end
    elseif current_wave <= #waves then
        if hasEnemiesFromWave(current_wave) then
            -- Still enemies from current wave, wait for them to be defeated
        elseif wave_delay_timer == 0 then
            -- All enemies defeated, start the delay
            wave_delay_timer = wave_delay
        elseif wave_delay_timer > 0 then
            -- Counting down delay
            if start_wave_early then
                wave_delay_timer = 0
                start_wave_early = false
            else
                wave_delay_timer = wave_delay_timer - dt
            end
            if wave_delay_timer <= 0 then
                -- Delay complete, start next wave
                if current_wave < #waves then
                    current_wave = current_wave + 1
                    wave_active = true
                    enemies_spawned_in_wave = 0
                    spawn_timer = 0
                    wave_delay_timer = 0
                else
                    -- Game over or something, all waves completed
                    wave_delay_timer = 0
                end
            end
        end
    end

    pulsate_time = pulsate_time + dt

    -- Move enemies
    for _, enemy in ipairs(enemies) do
        local data = enemies_data[enemy]
        if data.health > 0 then
            if data.current_index <= #data.path then
                local current_tile = data.path[data.current_index]
                local tile_pos = {(current_tile.x - GRID_SIZE / 2) * TILE_SPACING, 0, (current_tile.z - GRID_SIZE / 2) * TILE_SPACING}
                local dist = distance(enemy.position, tile_pos)
                if dist < 0.5 then
                    data.current_index = data.current_index + 1
                else
                    local dir = normalize({tile_pos[1] - enemy.position[1], tile_pos[2] - enemy.position[2], tile_pos[3] - enemy.position[3]})
                    enemy.position = {enemy.position[1] + dir[1] * data.speed * dt, enemy.position[2] + dir[2] * data.speed * dt, enemy.position[3] + dir[3] * data.speed * dt}
                end
            else
                -- Reached end, destroy
                enemy:destroy()
                enemies_data[enemy] = nil
                -- Will be removed in next loop
            end
        end
    end

    -- Update enemies: remove dead or finished ones
    for i = #enemies, 1, -1 do
        local enemy = enemies[i]
        local data = enemies_data[enemy]
        if not data or data.health <= 0 or data.current_index > #data.path then
            if data then 
                if data.health <= 0 then
                    -- Enemy killed, add score based on type
                    score = score + enemy_types[data.type].hp
                elseif data.current_index > #data.path then
                    -- Enemy reached end, penalty
                    score = math.max(0, score - 50)
                end
                enemies_data[enemy] = nil 
            end
            enemy:destroy()
            table.remove(enemies, i)
        end
    end

    -- Update towers: shoot at enemies in range
    for _, tower in ipairs(towers) do
        local tower_data = towers_data[tower]
        tower_data.lastShot = tower_data.lastShot + dt
        -- Find closest enemy in range
        local target = nil
        local minDist = tower_data.range
        for _, enemy in ipairs(enemies) do
            local dist = distance(tower.position, enemy.position)
            if dist < minDist then
                target = enemy
                minDist = dist
            end
        end
        -- Rotate weapon towards target
        if target then
            local weapon = tower_data.weapon
            local dir = normalize({target.position[1] - weapon.position[1], 0, target.position[3] - weapon.position[3]})
            local target_angle = math.atan2(dir[1], dir[3])
            tower_data.current_angle = lerp_angle(tower_data.current_angle, target_angle, tower_data.rotationSpeed * dt)
            local half_angle = tower_data.current_angle / 2
            weapon.rotation = {0, math.sin(half_angle), 0, math.cos(half_angle)}
        end
        if tower_data.lastShot >= 1 / tower_data.fireRate and target then
            -- Check if aimed roughly at target
            local dir = normalize({target.position[1] - tower.position[1], 0, target.position[3] - tower.position[3]})
            local target_angle = math.atan2(dir[1], dir[3])
            local diff = target_angle - tower_data.current_angle
            diff = ((diff + math.pi) % (2 * math.pi)) - math.pi
            if math.abs(diff) < AIM_TOLERANCE then
                -- Shoot: spawn projectile
                spawnProjectile(tower.position, target, tower_data.damage, tower_data.ammo, tower_data.speed, tower_data.scale)
                -- Optional: add visual effect or sound
                tower_data.lastShot = 0
            end
        end
    end

    -- Update projectiles
    for _, proj in ipairs(projectiles) do
        local data = projectiles_data[proj]
        if data and enemies_data[data.target] then
            local target_pos = {data.target.position[1], PROJECTILE_OFFSET_Y, data.target.position[3]}
            local dir = normalize({target_pos[1] - proj.position[1], 0, target_pos[3] - proj.position[3]})
            local angle = math.atan2(dir[1], dir[3])
            local half_angle = angle / 2
            proj.rotation = {0, math.sin(half_angle), 0, math.cos(half_angle)}
            proj.position = {proj.position[1] + dir[1] * data.speed * dt, PROJECTILE_OFFSET_Y, proj.position[3] + dir[3] * data.speed * dt}
            local dist = math.sqrt((proj.position[1] - data.target.position[1])^2 + (proj.position[3] - data.target.position[3])^2)
            if dist < 0.5 then
                enemies_data[data.target].health = enemies_data[data.target].health - data.damage
                proj:destroy()
                projectiles_data[proj] = nil
            end
        else
            -- Target dead or invalid, destroy projectile
            proj:destroy()
            projectiles_data[proj] = nil
        end
    end

    -- Remove destroyed projectiles
    for i = #projectiles, 1, -1 do
        if not projectiles_data[projectiles[i]] then
            table.remove(projectiles, i)
        end
    end

    -- Tower placement
    if camera ~= Lumix.Entity.NULL then
        local cam_comp = camera:getComponent("camera")
        if cam_comp then
            local ray = cam_comp:getRay({mouse_x, mouse_y})
            -- Intersect with y=0 plane
            if ray.dir[2] ~= 0 then
                local t = -ray.origin[2] / ray.dir[2]
                if t > 0 then
                    local pos = {
                        ray.origin[1] + t * ray.dir[1],
                        0,
                        ray.origin[3] + t * ray.dir[3]
                    }
                    -- Snap to grid
                    local grid_x = math.floor((pos[1] / TILE_SPACING) + GRID_SIZE / 2 + 0.5)
                    local grid_z = math.floor((pos[3] / TILE_SPACING) + GRID_SIZE / 2 + 0.5)
                    if grid_x >= 1 and grid_x <= GRID_SIZE and grid_z >= 1 and grid_z <= GRID_SIZE then
                        local snapped_pos = {
                            (grid_x - GRID_SIZE / 2) * TILE_SPACING,
                            TOWER_OFFSET_Y,
                            (grid_z - GRID_SIZE / 2) * TILE_SPACING
                        }
                        placeholder_tower.position = snapped_pos
                        if left_click and isTilePlaceable(grid_x, grid_z) then
                            placeTower(grid_x, grid_z, selected_type)
                        end
                    else
                        placeholder_tower.position = {0, -100, 0}
                    end
                else
                    placeholder_tower.position = {0, -100, 0}
                end
            else
                placeholder_tower.position = {0, -100, 0}
            end
        end
    else
        placeholder_tower.position = {0, -100, 0}
    end
    local pulsate_scale = 0.8 + 0.1 * math.sin(pulsate_time * 2)
    placeholder_tower.scale = {pulsate_scale, pulsate_scale, pulsate_scale}
    left_click = false

    -- Update score display
    if score_text then
        score_text.gui_text.text = "Score: " .. tostring(score)
    end
    if wave_text then
        wave_text.gui_text.text = "Wave: " .. tostring(current_wave)
    end
end

function onInputEvent(event)
    if event.type == "button" then
        if event.device.type == "keyboard" then
            if event.key_id == 49 and event.down then  -- '1'
                selected_type = 1
            elseif event.key_id == 50 and event.down then  -- '2'
                selected_type = 2
            elseif event.key_id == 51 and event.down then  -- '3'
                selected_type = 3
            elseif event.key_id == 52 and event.down then  -- '4'
                selected_type = 4
            end
            if selected_type ~= old_selected_type then
                local pos = placeholder_tower.position
                placeholder_tower:destroy()
                placeholder_tower = this.world:createEntityEx({
                    position = pos,
                    scale = {0.8, 0.8, 0.8},
                    model_instance = {source = tower_types[selected_type].model}
                })
                old_selected_type = selected_type
            end
        elseif event.device.type == "mouse" and event.key_id == 0 and event.down then
            left_click = true
        end
    elseif event.type == "axis" and event.device.type == "mouse" then
        mouse_x = event.x_abs
        mouse_y = event.y_abs
    end
end

-- helper: check if tile is placeable (in bounds and not on path or river)
function isTilePlaceable(x, z)
    if x < 1 or x > GRID_SIZE or z < 1 or z > GRID_SIZE then return false end
    if path_set and path_set[x .. "," .. z] then return false end
    if river_set and river_set[x .. "," .. z] then return false end
    return true
end
