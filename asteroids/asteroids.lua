local lmath = require "chess/math"

local WORLD_EXTENT = 32 -- Base orthographic half-size; X extent derives from aspect.
local WORLD_EXTENT_X -- Computed from camera aspect.
local WORLD_EXTENT_Z -- Z extent equals WORLD_EXTENT.
local STAR_COUNT = 200 -- Background star field density.
local STAR_SCALE = 0.1 -- Visual size for stars.
local PLANET_COUNT = 2 -- Background planet count.
local PLANET_MIN_SCALE = 2.0 -- Min planet scale.
local PLANET_MAX_SCALE = 4.5 -- Max planet scale.
local SHIP_MODEL = "asteroids/models/Vehicles/Spaceship_RaeTheRedPanda.fbx" -- Player ship mesh.
local SHIP_SCALE = 0.2 -- Ship model scale in world units.
local SHIP_RADIUS = 1.5 -- Collision radius for ship hits.
local SHIP_THRUST = 10 -- Base acceleration per second.
local SHIP_TURN_SPEED = 4.2 -- Radians per second.
local SHIP_DAMPING = 1 -- Velocity damping per frame.
local SHIP_INVULN_TIME = 2.0 -- Post-hit invulnerability seconds.
local SHIP_BOOST_MULT = 1.8 -- Speed multiplier while boosting.
local SHIP_BOOST_MAX = 2.0 -- Max boost energy.
local SHIP_BOOST_DRAIN = 1.2 -- Boost energy drained per second.
local SHIP_BOOST_RECHARGE = 0.7 -- Boost energy regen per second.
local BOOST_BAR_WIDTH = 220 -- GUI width in pixels.
local BOOST_BAR_HEIGHT = 14 -- GUI height in pixels.
local PICKUP_SPAWN_INITIAL = 6.0 -- First pickup delay.
local PICKUP_SPAWN_MIN = 8.0 -- Min respawn delay after pickup.
local PICKUP_SPAWN_MAX = 14.0 -- Max respawn delay after pickup.
local PICKUP_MAX_ACTIVE = 3 -- Cap on concurrent pickups.
local PICKUP_RADIUS = 1.0 -- Collision radius for pickup triggers.

local BULLET_MODEL = "/engine/models/sphere.fbx" -- Bullet mesh.
local BULLET_SCALE = 0.2 -- Bullet size in world units.
local BULLET_SPEED = 26 -- Bullet speed relative to ship.
local BULLET_TTL = 1.3 -- Bullet lifetime seconds.

local VFX_MUZZLE_FLASH = "asteroids/particles/muzzle_flash.pat" -- Shot flash.
local VFX_HIT_SPARK = "asteroids/particles/hit_spark.pat" -- Impact spark.
local VFX_EXPLOSION = "asteroids/particles/explosion.pat" -- Asteroid or ship explosion.
local VFX_TRAIL = "asteroids/particles/projectile_trail.pat" -- Bullet trail.
local VFX_THRUST = "asteroids/particles/ship_exhaust.pat" -- Ship exhaust plume.

local SHIP_THRUST_VFX_OFFSET = 0.5 -- Offset behind ship for exhaust.

local BASE_FIRE_COOLDOWN = 0.35 -- Seconds between shots.
local RAPID_FIRE_COOLDOWN = 0.15 -- Seconds between shots with powerup.

local ASTEROID_MODELS_LARGE = {
	"asteroids/models/Environment/Rock_Large_1.fbx",
	"asteroids/models/Environment/Rock_Large_2.fbx",
	"asteroids/models/Environment/Rock_Large_3.fbx"
}

local ASTEROID_MODELS_SMALL = {
	"asteroids/models/Environment/Rock_1.fbx",
	"asteroids/models/Environment/Rock_2.fbx",
	"asteroids/models/Environment/Rock_3.fbx",
	"asteroids/models/Environment/Rock_4.fbx"
}

local PLANET_MODELS = {
	"asteroids/models/Environment/Planet_1.fbx",
	"asteroids/models/Environment/Planet_2.fbx",
	"asteroids/models/Environment/Planet_3.fbx",
	"asteroids/models/Environment/Planet_4.fbx",
	"asteroids/models/Environment/Planet_5.fbx",
	"asteroids/models/Environment/Planet_6.fbx",
	"asteroids/models/Environment/Planet_7.fbx",
	"asteroids/models/Environment/Planet_8.fbx",
	"asteroids/models/Environment/Planet_9.fbx",
	"asteroids/models/Environment/Planet_10.fbx",
	"asteroids/models/Environment/Planet_11.fbx"
}

local ASTEROID_RADIUS_BY_MODEL = {
	["asteroids/models/Environment/Rock_1.fbx"] = 2.1,
	["asteroids/models/Environment/Rock_2.fbx"] = 2.0,
	["asteroids/models/Environment/Rock_3.fbx"] = 2.2,
	["asteroids/models/Environment/Rock_4.fbx"] = 1.8,
	["asteroids/models/Environment/Rock_Large_1.fbx"] = 4.7,
	["asteroids/models/Environment/Rock_Large_2.fbx"] = 5.9,
	["asteroids/models/Environment/Rock_Large_3.fbx"] = 4.4
}

local PICKUP_TYPES = {
	{
		id = "rapid",
		model = "asteroids/models/Items/Pickup_Thunder.fbx",
		duration = 8.0,
		label = "Rapid Fire"
	},
	{
		id = "shield",
		model = "asteroids/models/Items/Pickup_Sphere.fbx",
		duration = 10.0,
		label = "Shield"
	},
	{
		id = "life",
		model = "asteroids/models/Items/Pickup_Health.fbx",
		duration = 0,
		label = "+1 Life"
	}
}

local KEY_W = LumixAPI.Keycode.W
local KEY_A = LumixAPI.Keycode.A
local KEY_S = LumixAPI.Keycode.S
local KEY_D = LumixAPI.Keycode.D
local KEY_SPACE = LumixAPI.Keycode.SPACE
local KEY_R = LumixAPI.Keycode.R
local KEY_SHIFT = LumixAPI.Keycode.SHIFT

-- Gamepad button constants (tested on xbox controller)
local GPAD_BUTTON_START = 7  -- Restart
local GPAD_AXIS_LEFT_X = 0  -- Turn left/right (right stick X)
local GPAD_AXIS_LEFT_Y = 1  -- Thrust forward/backward (right stick Y)
local GPAD_AXIS_LEFT_TRIGGER = 4  -- Left trigger (boost)
local GPAD_AXIS_RIGHT_TRIGGER = 5  -- Right trigger (shoot)

local ship = {
	entity = nil,
	pos = {0, 0, 0},
	vel = {0, 0, 0},
	rot = 0,
	fire_timer = 0,
	invuln = 0,
	shield = false,
	thrust_vfx_entity = nil,
	boost_energy = SHIP_BOOST_MAX
}

local world_extents_ready = false
local stars_spawned = false
local planets_spawned = false

local bullets = {}
local asteroids = {}
local pickups = {}
local vfx_entities = {}

local camera_entity = nil
local score = 0
local lives = 3
local game_over = false
local wave = 1
local crash_waiting = false

local keys_down = {}
local keys_pressed = {}

local gamepad_axes = {}
local gamepad_buttons_down = {}
local gamepad_buttons_pressed = {}

local canvas = nil
local score_text = nil
local lives_text = nil
local wave_text = nil
local power_text = nil
local gameover_text = nil
local crash_text = nil
local boost_bar_bg = nil
local boost_bar_fill = nil

local pickup_timer = PICKUP_SPAWN_INITIAL
local active_powerup = {id = nil, timer = 0, label = ""}

local function randRange(min_val, max_val)
	return min_val + math.random() * (max_val - min_val)
end

local function pickRandom(list)
	return list[math.random(1, #list)]
end

local function spawnVFX(source, position, ttl)
	local e = this.world:createEntityEx({
		position = position,
		particle_emitter = {source = source, autodestroy = true}
	})
	table.insert(vfx_entities, {entity = e, ttl = ttl or 1.0})
	return e
end

local function spawnMuzzleFlash(position)
	spawnVFX(VFX_MUZZLE_FLASH, position, 0.35)
end

local function spawnHitSpark(position)
	spawnVFX(VFX_HIT_SPARK, position, 0.6)
end

local function spawnExplosion(position)
	spawnVFX(VFX_EXPLOSION, position, 1.6)
end

local function makeLookAt(from_pos, to_pos)
	-- Build a look-at quaternion from positions for the top-down camera.
	local dir = {
		to_pos[1] - from_pos[1],
		to_pos[2] - from_pos[2],
		to_pos[3] - from_pos[3]
	}
	local horiz = math.sqrt(dir[1] * dir[1] + dir[3] * dir[3])
	if horiz < 0.0001 then
		horiz = 0.0001
	end
	local yaw = math.atan2(dir[1], dir[3]) + math.pi
	local pitch = -math.atan2(dir[2], horiz)
	return lmath.mulQuat(lmath.makeQuatFromYaw(yaw), lmath.makeQuatFromPitch(pitch))
end

local function wrapPosition(pos)
	-- Screen-space wrap so objects re-enter on the opposite edge.
	local wrapped = false
	if pos[1] > WORLD_EXTENT_X then pos[1] = -WORLD_EXTENT_X; wrapped = true end
	if pos[1] < -WORLD_EXTENT_X then pos[1] = WORLD_EXTENT_X; wrapped = true end
	if pos[3] > WORLD_EXTENT_Z then pos[3] = -WORLD_EXTENT_Z; wrapped = true end
	if pos[3] < -WORLD_EXTENT_Z then pos[3] = WORLD_EXTENT_Z; wrapped = true end
	return wrapped
end

local function spawnStars()
	for i = 1, STAR_COUNT do
		local pos = {
			randRange(-WORLD_EXTENT_X, WORLD_EXTENT_X),
			randRange(-20, -15),
			randRange(-WORLD_EXTENT_Z, WORLD_EXTENT_Z)
		}
		this.world:createEntityEx({
			position = pos,
			scale = {STAR_SCALE, STAR_SCALE, STAR_SCALE},
			model_instance = {source = "/engine/models/sphere.fbx"}
		})
	end
end

local function spawnPlanets()
	for i = 1, PLANET_COUNT do
		local pos = {
			randRange(-WORLD_EXTENT_X, WORLD_EXTENT_X),
			randRange(-12.0, -8.0),
			randRange(-WORLD_EXTENT_Z, WORLD_EXTENT_Z)
		}
		local scale = randRange(PLANET_MIN_SCALE, PLANET_MAX_SCALE)
		local rot = lmath.makeQuatFromYaw(randRange(0, math.pi * 2))
		this.world:createEntityEx({
			position = pos,
			rotation = rot,
			scale = {scale, scale, scale},
			model_instance = {source = pickRandom(PLANET_MODELS)}
		})
	end
end

local function refreshWorldExtentsFromCamera()
	-- Derive horizontal bounds from orthographic size and aspect ratio.
	if not camera_entity or camera_entity == Lumix.Entity.NULL then
		return false
	end
	local width = camera_entity.camera.screen_width
	local height = camera_entity.camera.screen_height
	if width <= 0 or height <= 0 then
		return false
	end
	local aspect = width / height
	WORLD_EXTENT_X = WORLD_EXTENT * aspect
	WORLD_EXTENT_Z = WORLD_EXTENT
	return true
end

local function destroyEntity(entity)
	if not entity or entity == Lumix.Entity.NULL then
		return
	end
	entity:destroy()
end

local function clearEntityList(list)
	for i = #list, 1, -1 do
		destroyEntity(list[i].entity)
		table.remove(list, i)
	end
end

local function clearList(list)
	for i = #list, 1, -1 do
		table.remove(list, i)
	end
end

local function setEntityYaw(entity, yaw)
	entity.rotation = lmath.makeQuatFromYaw(yaw)
end

local function resetThrustVfx()
	destroyEntity(ship.thrust_vfx_entity)
	ship.thrust_vfx_entity = nil
	local forward = lmath.yawToDir(ship.rot)
	-- Keep exhaust aligned behind the ship regardless of wrap or rotation.
	ship.thrust_vfx_entity = this.world:createEntityEx({
		name = "thrust_vfx",
		position = {
			ship.pos[1] - forward[1] * SHIP_THRUST_VFX_OFFSET,
			ship.pos[2],
			ship.pos[3] - forward[3] * SHIP_THRUST_VFX_OFFSET
		},
		particle_emitter = {source = VFX_THRUST, autodestroy = false}
	})
end

local function resetShip()
	destroyEntity(ship.entity)
	ship.entity = nil
	destroyEntity(ship.thrust_vfx_entity)
	ship.thrust_vfx_entity = nil
	ship.pos = {0, 0, 0}
	ship.vel = {0, 0, 0}
	ship.rot = 0
	ship.fire_timer = 0
	ship.invuln = SHIP_INVULN_TIME
	ship.shield = false
	ship.boost_energy = SHIP_BOOST_MAX

	ship.entity = this.world:createEntityEx({
		position = {ship.pos[1], ship.pos[2], ship.pos[3]},
		scale = {SHIP_SCALE, SHIP_SCALE, SHIP_SCALE},
		model_instance = {source = SHIP_MODEL}
	})
	setEntityYaw(ship.entity, ship.rot)
	resetThrustVfx()
end

local function spawnAsteroid(size_id, pos, vel)
	-- Pick a model, scale its collision radius, and randomize spin.
	local model_list = (size_id == "large") and ASTEROID_MODELS_LARGE or ASTEROID_MODELS_SMALL
	local model = pickRandom(model_list)
	local scale = (size_id == "large") and 0.6 or 0.35
	local radius = (ASTEROID_RADIUS_BY_MODEL[model] or 1.0) * scale
	local asteroid_entity = this.world:createEntityEx({
		position = {pos[1], pos[2], pos[3]},
		scale = {scale, scale, scale},
		model_instance = {source = model}
	})
	table.insert(asteroids, {
		entity = asteroid_entity,
		pos = {pos[1], pos[2], pos[3]},
		vel = {vel[1], vel[2], vel[3]},
		size = size_id,
		radius = radius,
		rotation = {0, 0, 0, 1},
		angular_vel = (function()
			local axis = {randRange(-1, 1), randRange(-1, 1), randRange(-1, 1)}
			local len = math.sqrt(axis[1]^2 + axis[2]^2 + axis[3]^2)
			if len > 0.001 then
				axis[1] = axis[1] / len
				axis[2] = axis[2] / len
				axis[3] = axis[3] / len
			else
				axis = {0, 1, 0}
			end
			local speed = randRange(0.5, 2.0)
			return {axis[1] * speed, axis[2] * speed, axis[3] * speed}
		end)()
	})
end

local function spawnAsteroidWave(count)
	-- Spawn around the perimeter with inward-ish drift for pressure.
	local min_extent = math.min(WORLD_EXTENT_X, WORLD_EXTENT_Z)
	for i = 1, count do
		local angle = randRange(0, math.pi * 2)
		local dist = randRange(min_extent * 0.6, min_extent * 0.95)
		local pos = {math.cos(angle) * dist, 0, math.sin(angle) * dist}
		local speed = randRange(2.5, 4.5)
		local dir = {randRange(-1, 1), 0, randRange(-1, 1)}
		local mag = math.sqrt(dir[1] * dir[1] + dir[3] * dir[3])
		if mag < 0.1 then mag = 0.1 end
		dir[1] = dir[1] / mag
		dir[3] = dir[3] / mag
		local vel = {dir[1] * speed, 0, dir[3] * speed}
		spawnAsteroid("large", pos, vel)
	end
end

local function spawnBullet()
	-- Bullets inherit ship velocity to feel consistent while boosting.
	local forward = lmath.yawToDir(ship.rot)
	local pos = {
		ship.pos[1] + forward[1] * 1.6,
		ship.pos[2],
		ship.pos[3] + forward[3] * 1.6
	}
	local vel = {
		ship.vel[1] + forward[1] * BULLET_SPEED,
		0,
		ship.vel[3] + forward[3] * BULLET_SPEED
	}
	local bullet_entity = this.world:createEntityEx({
		position = {pos[1], pos[2], pos[3]},
		scale = {BULLET_SCALE, BULLET_SCALE, BULLET_SCALE},
		model_instance = {source = BULLET_MODEL}
	})
	bullet_entity:createComponent("particle_emitter")
	bullet_entity.particle_emitter.source = VFX_TRAIL
	bullet_entity.particle_emitter.autodestroy = false
	spawnMuzzleFlash({pos[1], pos[2], pos[3]})
	table.insert(bullets, {
		entity = bullet_entity,
		pos = pos,
		vel = vel,
		ttl = BULLET_TTL
	})
end

local function spawnPickup()
	local pick = PICKUP_TYPES[math.random(1, #PICKUP_TYPES)]
	local pos = {randRange(-WORLD_EXTENT_X * 0.75, WORLD_EXTENT_X * 0.75), 0, randRange(-WORLD_EXTENT_Z * 0.75, WORLD_EXTENT_Z * 0.75)}
	local base_rot = lmath.makeQuatFromPitch(math.pi * -0.5)
	local entity = this.world:createEntityEx({
		position = {pos[1], pos[2], pos[3]},
		rotation = base_rot,
		scale = {1.5, 1.5, 1.5},
		model_instance = {source = pick.model}
	})
	table.insert(pickups, {
		entity = entity,
		pos = {pos[1], pos[2], pos[3]},
		base_pos = {pos[1], pos[2], pos[3]},
		id = pick.id,
		label = pick.label,
		duration = pick.duration,
		drift_vel = {randRange(-0.6, 0.6), 0, randRange(-0.6, 0.6)},
		bob_phase = randRange(0, math.pi * 2),
		bob_speed = randRange(1.2, 2.0),
		bob_amp = randRange(0.2, 0.5),
		spin = randRange(0, math.pi * 2),
		spin_speed = randRange(1.0, 2.0),
		base_rot = base_rot
	})
end

local function setPowerup(id, duration, label)
	active_powerup.id = id
	active_powerup.timer = duration
	active_powerup.label = label
end

local function applyPickup(pickup)
	if pickup.id == "shield" then
		ship.shield = true
	end
	if pickup.id == "life" then
		lives = lives + 1
		return
	end
	if pickup.duration > 0 then
		setPowerup(pickup.id, pickup.duration, pickup.label)
	end
end

local function clearPowerup()
	active_powerup.id = nil
	active_powerup.timer = 0
	active_powerup.label = ""
end

local function updateGui()
	if score_text then
		score_text.gui_text.text = "Score: " .. tostring(score)
	end
	if lives_text then
		lives_text.gui_text.text = "Lives: " .. tostring(lives)
	end
	if wave_text then
		wave_text.gui_text.text = "Wave: " .. tostring(wave)
	end
	if power_text then
		if active_powerup.id then
			power_text.gui_text.text = active_powerup.label .. " " .. tostring(math.ceil(active_powerup.timer)) .. "s"
		else
			power_text.gui_text.text = ""
		end
	end
	if gameover_text then
		if game_over then
			gameover_text.gui_text.text = "GAME OVER - Press R to Restart"
		else
			gameover_text.gui_text.text = ""
		end
	end
	if crash_text then
		if crash_waiting and not game_over then
			crash_text.gui_text.text = "Press R to Respawn"
		else
			crash_text.gui_text.text = ""
		end
	end
	if boost_bar_fill then
		local ratio = 0
		if SHIP_BOOST_MAX > 0 then
			ratio = math.max(0, math.min(1, ship.boost_energy / SHIP_BOOST_MAX))
		end
		local fill_width = math.floor((BOOST_BAR_WIDTH - 4) * ratio)
		boost_bar_fill.gui_rect.left_points = 12
		boost_bar_fill.gui_rect.right_points = 12 + fill_width
	end
end

local function resetGame()
	clearEntityList(bullets)
	clearEntityList(asteroids)
	clearEntityList(pickups)
	clearList(vfx_entities)

	score = 0
	lives = 3
	wave = 1
	game_over = false
	crash_waiting = false
	clearPowerup()
	pickup_timer = PICKUP_SPAWN_INITIAL
	-- Clear input state
	keys_down = {}
	keys_pressed = {}
	gamepad_axes = {}
	gamepad_buttons_down = {}
	gamepad_buttons_pressed = {}
	resetShip()
	spawnAsteroidWave(4)
	updateGui()
end

function start()
	math.randomseed(os.time())

	WORLD_EXTENT_X = WORLD_EXTENT
	WORLD_EXTENT_Z = WORLD_EXTENT

	local cam_pos = {0, 100, 0}
	local cam_rot = makeLookAt(cam_pos, {0, 0, 0})
	camera_entity = this.world:createEntityEx({
		name = "camera",
		position = cam_pos,
		rotation = cam_rot,
		camera = {is_ortho = true, ortho_size = WORLD_EXTENT}
	})
	world_extents_ready = refreshWorldExtentsFromCamera()

	this.world:createEntityEx({
		name = "key_light",
		rotation = lmath.makeQuatFromPitch(-0.6),
		environment = {direct_intensity = 2.0, light_color = {1.0, 1.0, 1.0}, atmo_enabled = false}
	})

	local gui_module = this.world:getModule("gui")
	if gui_module then
		gui_module:getSystem():enableCursor(false)
	end

	canvas = this.world:createEntityEx({
		gui_canvas = {},
		gui_rect = {}
	})

	score_text = this.world:createEntityEx({
		gui_text = {text = "Score: 0", font_size = 48, color = {1.0, 1.0, 1.0, 1.0}, font = "ui/font/Kenney Future.ttf"},
		gui_rect = {left_points = 10, top_points = 10},
		parent = canvas
	})

	lives_text = this.world:createEntityEx({
		gui_text = {text = "Lives: 3", font_size = 48, color = {1.0, 1.0, 1.0, 1.0}, font = "ui/font/Kenney Future.ttf"},
		gui_rect = {left_points = 10, top_points = 60},
		parent = canvas
	})

	wave_text = this.world:createEntityEx({
		gui_text = {text = "Wave: 1", font_size = 48, color = {1.0, 1.0, 1.0, 1.0}, font = "ui/font/Kenney Future.ttf"},
		gui_rect = {left_relative = 1, left_points = -240, right_relative = 1, right_points = -10, top_points = 10},
		parent = canvas
	})

	power_text = this.world:createEntityEx({
		gui_text = {text = "", font_size = 36, color = {1.0, 1.0, 1.0, 1.0}, font = "ui/font/Kenney Future.ttf"},
		gui_rect = {left_relative = 0.5, left_points = -200, right_relative = 0.5, right_points = 200, top_points = 10},
		parent = canvas
	})

	gameover_text = this.world:createEntityEx({
		gui_text = {text = "", font_size = 60, horizontal_align = LumixAPI.TextHAlign.CENTER, vertical_align = LumixAPI.TextVAlign.MIDDLE, color = {1.0, 1.0, 1.0, 1.0}, font = "ui/font/Kenney Future.ttf"},
		gui_rect = {left_relative = 0.5, right_relative = 0.5, left_points = -400, right_points = 400, top_relative = 0.5, bottom_relative = 0.5, top_points = -50, bottom_points = 50},
		parent = canvas
	})

	crash_text = this.world:createEntityEx({
		gui_text = {text = "", font_size = 44, horizontal_align = LumixAPI.TextHAlign.CENTER, vertical_align = LumixAPI.TextVAlign.MIDDLE, color = {1.0, 1.0, 1.0, 1.0}, font = "ui/font/Kenney Future.ttf"},
		gui_rect = {left_relative = 0.5, right_relative = 0.5, left_points = -360, right_points = 360, top_relative = 0.5, bottom_relative = 0.5, top_points = 30, bottom_points = 90},
		parent = canvas
	})

	boost_bar_bg = this.world:createEntityEx({
		gui_rect = {left_relative = 0, right_relative = 0, top_relative = 0, bottom_relative = 0, left_points = 10, right_points = 10 + BOOST_BAR_WIDTH, top_points = 115, bottom_points = 115 + BOOST_BAR_HEIGHT},
		gui_image = {color = {0.1, 0.1, 0.1, 0.7}},
		parent = canvas
	})

	boost_bar_fill = this.world:createEntityEx({
		gui_rect = {left_relative = 0, right_relative = 0, top_relative = 0, bottom_relative = 0, left_points = 12, right_points = 12 + (BOOST_BAR_WIDTH - 4), top_points = 117, bottom_points = 117 + (BOOST_BAR_HEIGHT - 4)},
		gui_image = {color = {0.2, 0.85, 1.0, 0.9}},
		parent = canvas
	})

	resetGame()
end

function onInputEvent(event)
	if event.type == "button" and event.device and event.device.type == "keyboard" then
		keys_down[event.key_id] = event.down
		if event.down then
			keys_pressed[event.key_id] = true
		end
	elseif event.type == "button" and event.device and event.device.type == "gamepad" then
		gamepad_buttons_down[event.key_id] = event.down
		if event.down then
			gamepad_buttons_pressed[event.key_id] = true
		end
	elseif event.type == "axis" and event.device and event.device.type == "gamepad" then
		-- Gamepad axes: event.axis indicates which axis (0=LTRIGGER, 1=RTRIGGER, 2=LTHUMB, 3=RTHUMB)
		-- event.x, event.y contain the axis values
		if event.axis == 3 then  -- RTHUMB (right stick) - used for turning
			gamepad_axes[GPAD_AXIS_LEFT_X] = event.x
		elseif event.axis == 2 then  -- LTHUMB (left stick) - used for thrust
			gamepad_axes[GPAD_AXIS_LEFT_Y] = event.y
		elseif event.axis == 0 then  -- LTRIGGER
			gamepad_axes[GPAD_AXIS_LEFT_TRIGGER] = event.x
		elseif event.axis == 1 then  -- RTRIGGER
			gamepad_axes[GPAD_AXIS_RIGHT_TRIGGER] = event.x
		end
	end
end

local function consumeKey(key_id)
	if keys_pressed[key_id] then
		keys_pressed[key_id] = nil
		return true
	end
	return false
end

local function consumeGamepadButton(button_id)
	if gamepad_buttons_pressed[button_id] then
		gamepad_buttons_pressed[button_id] = nil
		return true
	end
	return false
end

local function updateVfxEntities(dt)
	for i = #vfx_entities, 1, -1 do
		local item = vfx_entities[i]
		item.ttl = item.ttl - dt
		if item.ttl <= 0 then
			table.remove(vfx_entities, i)
		end
	end
end

local function updateShipTimers(dt)
	ship.fire_timer = math.max(0, ship.fire_timer - dt)
	ship.invuln = math.max(0, ship.invuln - dt)

	if active_powerup.id then
		-- Expire timed powerups and clear shield when they end.
		active_powerup.timer = math.max(0, active_powerup.timer - dt)
		if active_powerup.timer <= 0 then
			clearPowerup()
			ship.shield = false
		end
	end
end

local function updateShipMovement(dt)
	local turn_input = 0
	if keys_down[KEY_A] then turn_input = turn_input + 1 end
	if keys_down[KEY_D] then turn_input = turn_input - 1 end
	-- Add gamepad left stick X axis for turning
	local gpad_turn = -(gamepad_axes[GPAD_AXIS_LEFT_X] or 0)
	turn_input = turn_input + gpad_turn
	ship.rot = ship.rot + turn_input * SHIP_TURN_SPEED * dt
	local forward = lmath.yawToDir(ship.rot)

	local thrust = 0
	if keys_down[KEY_W] then thrust = thrust + 1 end
	if keys_down[KEY_S] then thrust = thrust - 0.6 end
	-- Add gamepad left stick Y axis for thrust (negative Y = forward)
	local gpad_thrust = (gamepad_axes[GPAD_AXIS_LEFT_Y] or 0)
	thrust = thrust + gpad_thrust

	local boost_active = false
	local boost_input = keys_down[KEY_SHIFT] or ((gamepad_axes[GPAD_AXIS_LEFT_TRIGGER] or 0) > 0.5)
	if boost_input and ship.boost_energy > 0 and thrust > 0 then
		boost_active = true
		ship.boost_energy = math.max(0, ship.boost_energy - SHIP_BOOST_DRAIN * dt)
	else
		ship.boost_energy = math.min(SHIP_BOOST_MAX, ship.boost_energy + SHIP_BOOST_RECHARGE * dt)
	end

	if thrust ~= 0 then
		-- Apply thrust in facing direction, scaled by boost.
		local thrust_scale = boost_active and SHIP_BOOST_MULT or 1.0
		ship.vel[1] = ship.vel[1] + forward[1] * SHIP_THRUST * thrust * thrust_scale * dt
		ship.vel[3] = ship.vel[3] + forward[3] * SHIP_THRUST * thrust * thrust_scale * dt
	end

	-- Update thrust ribbon position
	if ship.thrust_vfx_entity and ship.thrust_vfx_entity ~= Lumix.Entity.NULL then
		ship.thrust_vfx_entity.position = {
			ship.pos[1] - forward[1] * SHIP_THRUST_VFX_OFFSET,
			ship.pos[2],
			ship.pos[3] - forward[3] * SHIP_THRUST_VFX_OFFSET
		}
	else
		resetThrustVfx()
	end

	ship.vel[1] = ship.vel[1] * SHIP_DAMPING
	ship.vel[3] = ship.vel[3] * SHIP_DAMPING

	ship.pos[1] = ship.pos[1] + ship.vel[1] * dt
	ship.pos[3] = ship.pos[3] + ship.vel[3] * dt
	local wrapped = wrapPosition(ship.pos)
	ship.entity.position = {ship.pos[1], ship.pos[2], ship.pos[3]}
	setEntityYaw(ship.entity, ship.rot)
	if wrapped then
		-- Reset exhaust when wrapping to avoid sudden long trails.
		resetThrustVfx()
	end
end

local function updateBullets(dt)
	for i = #bullets, 1, -1 do
		local b = bullets[i]
		b.ttl = b.ttl - dt
		b.pos[1] = b.pos[1] + b.vel[1] * dt
		b.pos[3] = b.pos[3] + b.vel[3] * dt
		wrapPosition(b.pos)
		b.entity.position = {b.pos[1], b.pos[2], b.pos[3]}
		if b.ttl <= 0 then
			destroyEntity(b.entity)
			table.remove(bullets, i)
		end
	end
end

local function updateAsteroids(dt)
	for i = #asteroids, 1, -1 do
		local a = asteroids[i]
		a.pos[1] = a.pos[1] + a.vel[1] * dt
		a.pos[3] = a.pos[3] + a.vel[3] * dt
		wrapPosition(a.pos)
		a.entity.position = {a.pos[1], a.pos[2], a.pos[3]}
		local speed = math.sqrt(a.angular_vel[1]^2 + a.angular_vel[2]^2 + a.angular_vel[3]^2)
		if speed > 0.001 then
			-- Integrate angular velocity into a quaternion rotation.
			local axis = {a.angular_vel[1]/speed, a.angular_vel[2]/speed, a.angular_vel[3]/speed}
			local angle = speed * dt
			local half = angle * 0.5
			local s = math.sin(half)
			local c = math.cos(half)
			local delta = {axis[1]*s, axis[2]*s, axis[3]*s, c}
			a.rotation = lmath.mulQuat(delta, a.rotation)
		end
		a.entity.rotation = a.rotation
	end
end

local function updatePickups(dt)
	for i = #pickups, 1, -1 do
		local p = pickups[i]
		p.base_pos[1] = p.base_pos[1] + p.drift_vel[1] * dt
		p.base_pos[3] = p.base_pos[3] + p.drift_vel[3] * dt
		wrapPosition(p.base_pos)
		p.bob_phase = p.bob_phase + p.bob_speed * dt
		p.spin = p.spin + p.spin_speed * dt
		p.pos[1] = p.base_pos[1]
		p.pos[2] = p.base_pos[2] + math.sin(p.bob_phase) * p.bob_amp
		p.pos[3] = p.base_pos[3]
		p.entity.position = {p.pos[1], p.pos[2], p.pos[3]}
		p.entity.rotation = lmath.mulQuat(p.base_rot, lmath.makeQuatFromYaw(p.spin))
		local dist_sq = lmath.distSquared(ship.pos, p.pos)
		if dist_sq < (SHIP_RADIUS + PICKUP_RADIUS) * (SHIP_RADIUS + PICKUP_RADIUS) then
			applyPickup(p)
			destroyEntity(p.entity)
			table.remove(pickups, i)
		end
	end
end

local function handleBulletAsteroidHits()
	for i = #bullets, 1, -1 do
		local b = bullets[i]
		local hit = false
		for j = #asteroids, 1, -1 do
			local a = asteroids[j]
			local dist_sq = lmath.distSquared(b.pos, a.pos)
			if dist_sq < (a.radius * a.radius) then
				destroyEntity(b.entity)
				table.remove(bullets, i)
				hit = true
				score = score + ((a.size == "large") and 20 or 50)
				spawnHitSpark({a.pos[1], a.pos[2], a.pos[3]})
				spawnExplosion({a.pos[1], a.pos[2], a.pos[3]})

				if a.size == "large" then
					-- Split large asteroids into two smaller ones.
					local angle = randRange(0, math.pi * 2)
					local speed = randRange(3.5, 6.0)
					local dir1 = {math.cos(angle), 0, math.sin(angle)}
					local dir2 = {-dir1[1], 0, -dir1[3]}
					spawnAsteroid("small", {a.pos[1], 0, a.pos[3]}, {dir1[1] * speed, 0, dir1[3] * speed})
					spawnAsteroid("small", {a.pos[1], 0, a.pos[3]}, {dir2[1] * speed, 0, dir2[3] * speed})
				end

				destroyEntity(a.entity)
				table.remove(asteroids, j)
				break
			end
		end
		if hit then
			break
		end
	end
end

local function handleShipAsteroidCollisions()
	if ship.invuln > 0 then
		return
	end
	for i = #asteroids, 1, -1 do
		local a = asteroids[i]
		local dist_sq = lmath.distSquared(ship.pos, a.pos)
		if dist_sq < (SHIP_RADIUS + a.radius) * (SHIP_RADIUS + a.radius) then
			if ship.shield then
				-- Shield absorbs one hit and grants brief invulnerability.
				ship.shield = false
				clearPowerup()
				ship.invuln = SHIP_INVULN_TIME
				spawnHitSpark({ship.pos[1], ship.pos[2], ship.pos[3]})
			else
				-- Destroy ship, then require respawn input unless game over.
				spawnExplosion({ship.pos[1], ship.pos[2], ship.pos[3]})
				lives = lives - 1
				if lives <= 0 then
					game_over = true
				else
					destroyEntity(ship.entity)
					ship.entity = nil
					crash_waiting = true
				end
			end
			destroyEntity(a.entity)
			table.remove(asteroids, i)
			break
		end
	end
end

local function handleWaveProgress()
	-- Advance to a harder wave once all asteroids are cleared.
	if #asteroids == 0 then
		wave = wave + 1
		spawnAsteroidWave(3 + wave)
	end
end

function update(dt)
	if not world_extents_ready then
		world_extents_ready = refreshWorldExtentsFromCamera()
	end
	if world_extents_ready and not stars_spawned then
		spawnStars()
		stars_spawned = true
	end
	if world_extents_ready and not planets_spawned then
		spawnPlanets()
		planets_spawned = true
	end
	if crash_waiting then
		-- Pause gameplay while waiting for manual respawn.
		if consumeKey(KEY_R) or consumeGamepadButton(GPAD_BUTTON_START) then
			crash_waiting = false
			resetShip()
		end
		updateGui()
		return
	end

	if not ship.entity then
		return
	end

	updateVfxEntities(dt)

	if game_over then
		-- Allow restart from a clean state.
		if consumeKey(KEY_R) or consumeGamepadButton(GPAD_BUTTON_START) then
			resetGame()
		end
		updateGui()
		return
	end

	updateShipTimers(dt)
	updateShipMovement(dt)

	local fire_cooldown = (active_powerup.id == "rapid") and RAPID_FIRE_COOLDOWN or BASE_FIRE_COOLDOWN
	local right_trigger_pressed = (gamepad_axes[GPAD_AXIS_RIGHT_TRIGGER] or 0) > 0.5
	if (keys_down[KEY_SPACE] or right_trigger_pressed) and ship.fire_timer <= 0 then
		spawnBullet()
		ship.fire_timer = fire_cooldown
	end

	pickup_timer = pickup_timer - dt
	if pickup_timer <= 0 and #pickups < PICKUP_MAX_ACTIVE then
		spawnPickup()
		pickup_timer = randRange(PICKUP_SPAWN_MIN, PICKUP_SPAWN_MAX)
	end

	updateBullets(dt)
	updateAsteroids(dt)
	updatePickups(dt)
	handleBulletAsteroidHits()
	handleShipAsteroidCollisions()
	handleWaveProgress()

	updateGui()
end
