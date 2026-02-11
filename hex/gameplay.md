
# Hex — Gameplay (combat-free)

## Vision

A turn-based, roguelike, hex-grid survival and building game with a hardcore, map-focused design and no combat. Players manage placement and development on a hex map, balancing resources, infrastructure, exploration and avoidance of environmental hazards. Art and models will reuse assets from the `hex/models` folder (fantasy / historical palette).

## Player goals

- Short-term: keep population/resources alive for the next day/turn, secure essential services (water, food, shelter), and repair critical infrastructure.
- Mid-term: expand and optimize the settlement, establish safe supply routes, and automate repetitive tasks.
- Long-term: complete map-specific objectives (reach evacuation point, survive X turns, establish a self-sustaining colony, restore a ruined network).


## Core mechanics

- Territorial Expansion: Start with one hex; each turn, players can only build or claim new hexes adjacent to already owned ones, encouraging strategic growth and planning.
- Hex Building & Zoning: place structures or change tile states (farms, water catchments, workshops, bridges). Terrain and adjacency affect yields and efficiency.
- Turn-Based Actions: each actor/structure has an action budget.
 - Turn-Based Actions: the player receives an action budget each turn equal to their current population; actions are spent on building, recycling, upgrading and trading.
- Survival Resources & Logistics: manage food, water, raw materials, fuel and power; design supply lines and transfer priorities.
- Environmental Hazards: storms, floods, landslides, blight, toxic mists — these force rerouting, temporary evacuation, or specialized structure placement.
- Procedural Generation: Maps, resource distributions, events, and hazards are randomly generated each run for high replayability and emergent challenges.

## Modes & Scenarios

- Sandbox/Endless: procedurally generated maps with escalating environmental difficulty and resource scarcity for leaderboard survival.

## Progression & Rewards
## Progression & Rewards

- Tech tree of structures, automation modules and routing tools unlocked by milestones (survived days, discovered caches).
- Persistent meta-progression options (quality-of-life upgrades, improved starting equipment) for repeat playthroughs while keeping core mode hardcore.
- Roguelike elements: earn permanent unlocks between runs, such as rare recipes or starting bonuses; procedural elements ensure each playthrough feels unique with random discoveries and escalating challenges.

## Level design notes

- Map size: medium to large hex maps (e.g., 40×40) for exploration and logistics.
- Hex variance: resource-rich nodes, unstable terrain, seasonal hazard zones and buildable plots should encourage meaningful placement and routing decisions.
- Objectives: use a mix of mandatory goals and optional puzzles/side-objectives to create varied risk/reward choices.

## Turn progress

Each turn proceeds as follows:

- Player actions: the player spends their action budget (equal to population) on build, recycle, upgrade, sell/buy.
- Production: resources are produced based on owned tiles and buildings.
- Consumption: resources are consumed based on population and buildings (consumption is applied before population growth).
- Random event: a random event may occur, e.g., fire, storm, etc.
- Population change: apply growth or shrink rules (see Population).
- End of turn.

## Placement rules

The player can build only on tiles that meet placement rules:

- By default, a tile must not be a mountain or deep water tile to be buildable.
- There are no trees on the tile. They must be cut before.
- A tile must be adjacent to an already owned tile to be buildable (the starting castle counts as an owned tile).
- Exceptions and special placements:
	- Mine: can only be built on mountain tiles.
	- Well: must be placed on a tile adjacent to water; each well produces water and extends the player's buildable area by one hex radius from that well.
	- Lumbermill: must be placed adjacent to a tile with trees.

## Resources

- gold
- grain
- water
- wood
- stone
- tools

## Stats

- current population
- max population
- happiness

## Buildings

A single castle is placed at the beginning of the game. It provides the player with a base where they can build their next buildings. The player cannot build or demolish the castle.

| Building     | Cost                                    | Notes                                              | Production                              |
|--------------|-----------------------------------------|----------------------------------------------------|-----------------------------------------|
| Well         | 2 stones, 1wood, 1 tool                 | Must be placed adjacent to water                   | +1 water/turn                           |
| Home         | 2 stones, 2 wood, 1 tool                |                                                    | +1 population limit                     |
| Field        | 1 wood, 1 tool                          |                                                    | +1 grain/turn                           |
| Mine         | 4 woods, 2 stones, 3 tools              | Must be built on mountain tiles                    | +1 stone/turn                           |
| Lumbermill   | 1 stone, 1 wood, 1 tool                 | Must be placed adjacent to trees                   | +1 wood/turn                            |
| Tavern       | 3 stones, 3 wood, 2 tools               |                                                    | +10 happiness                           |
| Blacksmith   | 3 stones, 3 wood, 3 tools               |                                                    | +1 tool/turn                            |
| Windmill     | 3 stones, 2 wood, 4 tools               | can not be placed to another windmill              | +1 action                               |
| Market       | 5 stones, 5 wood, 5 tools               | Enables trade; prices may vary                     | none                                    |
| Castle       | N/A                                     | Starting building; cannot be built or demolished   | none                                    |

## Population

Each turn, population can grow by 1 if:

- happiness is not 0
- there are enough homes
- there is enough grain and water

### Population shrinking

- Population shrinks by 1 every turn happiness is 0
- Population shrinks by 1 for every missing grain or water. For example, if the population is 5 and only 2 grain units are available at the beginning of a turn, 2 grains are consumed and the population shrinks to 2.

Each population unit requires 1 grain and 1 water per turn. The order of resolution is defined in the Turn progress section: Consumption is applied before Population change.

Growth conditions (applied after consumption and shrink):

- Population may increase by +1 if all the following are true:
	- happiness > 0
	- there is at least one free home per new unit
	- the population limit has not been reached
	- there is at least 1 grain and 1 water available per population unit (after Consumption)

Shrink rules:

- Population decreases by 1 for each missing grain or water unit during the Consumption phase. Example: if population is 5 and only 2 grain units are available, 2 grains are consumed and population shrinks to 2.
- Population decreeses if the population limit shrinks - e.g. if player destroys a home.

## Happiness

Happiness is a persistent numeric stat (minimum 0). Suggested default starting happiness: 10 (subject to balance).

- Happiness can be increased by buildings such as taverns.
- Each population unit decreases happiness by 1.
- Each mine or lumbermill decreases happiness by 1.
- Happiness cannot go below 0. Population growth requires happiness > 0.
- Number of player's actions per turn halved if happiness is 0.

## Player actions

Each turn, the player can perform as many actions as they have population units. Possible actions are:

- cut trees - +4 wood, -1 tool, make the tile ready for buildings
- build a building
- recycle a building
- upgrade a building
- sell/buy on a market
- react to random event (fix buildings, extinguish fire, ...)

## Random event

Every turn one random event can occur with some probability. Possible events are:

- fire - random building catches a fire. User must extinguish the fire (consumes 2 actions) on the same turn or the building is destroyed. If not extinguished, there's a possibility the fire spreads to random adjacent building.
- drought - water production is halved. Player can not do anything about it.
- flood - food production is 0 this turn. Player can spend all his action for flood prevention so food production is kept.
- thieves - random amount of random resource is stolen. Player can use all his actions to catch the thieves and get all resources back.
- forest fire - random forest is burning. User can extinguish the fire (consumes 1 action) on the same turn or the building is destroyed.
- earthquake - some buildings are damaged. They do not produce any output. User must repair them (costs 1 action per building) for production to start.
- lightning - random building is completely destoryed.

# TODO
- tech tree
- balance
- upgrading a building