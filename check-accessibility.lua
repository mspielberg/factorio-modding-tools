if not data then data = { raw = require("data-raw") } end
local ASSEMBLER = "assembling-machine"
local CRAFTING_CATEGORY = "crafting-category"
local ENTITY = "entity"
local FLUID = "fluid"
local ITEM = "item"
local RECIPE = "recipe"
local RESOURCE_CATEGORY = "resource-category"
local TECHNOLOGY = "technology"

if not log then
  log = function(s) print(s) end
end

local debug = {
  -- ["automation-science-pack"] = true,
}

local changed = true

local ok = {}

local function is_ok(proto_type, proto_name)
  return ok[proto_type] and ok[proto_type][proto_name]
end

local function mark_ok(proto_type, proto_name, cause)
  if not ok[proto_type] then
    ok[proto_type] = {}
  end
  if not ok[proto_type][proto_name] then
    log(proto_type.." "..proto_name.." is accessible via "..cause)
    ok[proto_type][proto_name] = true
    changed = true
  end
end

-- https://wiki.factorio.com/Prototype/Entity#Extensions
local ENTITY_TYPES = {
  "accumulator",
  "artillery-turret",
  "beacon",
  "boiler",
  "arithmetic-combinator",
  "decider-combinator",
  "constant-combinator",
  "container",
  "logistic-container",
  "assembling-machine",
  "rocket-silo",
  "furnace",
  "electric-pole",
  "combat-robot",
  "construction-robot",
  "logistic-robot",
  "gate",
  "generator",
  "heat-pipe",
  "inserter",
  "lab",
  "lamp",
  "land-mine",
  "mining-drill",
  "offshore-pump",
  "pipe",
  "pipe-to-ground",
  "power-switch",
  "programmable-speaker",
  "pump",
  "radar",
  "straight-rail",
  "rail-chain-signal",
  "rail-signal",
  "reactor",
  "roboport",
  "solar-panel",
  "storage-tank",
  "train-stop",
  "loader",
  "splitter",
  "transport-belt",
  "underground-belt",
  "turret",
  "ammo-turret",
  "electric-turret",
  "fluid-turret",
  "car",
  "artillery-wagon",
  "cargo-wagon",
  "fluid-wagon",
  "locomotive",
  "wall",
}

-- https://wiki.factorio.com/Prototype/Item#Extensions
local ITEM_TYPES = {
  "ammo",
  "capsule",
  "gun",
  "item",
  "item-with-entity-data",
  "item-with-label",
  "item-with-inventory",
  "item-with-tags",
  "selection-tool",
  "module",
  "rail-planner",
  "tool",
  "armor",
  "repair-tool",
}

local function entity_prototype(name)
  for _, proto_type in pairs(ENTITY_TYPES) do
    local protos = data.raw[proto_type] or {}
    if protos[name] then
      return protos[name]
    end
  end
  error("couldn't find entity "..name)
end

local function item_prototype(name)
  for _, proto_type in pairs(ITEM_TYPES) do
    local protos = data.raw[proto_type]
    if protos[name] and protos[name].stack_size then
      return protos[name]
    end
  end
  error("couldn't find item "..name)
end

local function mining_results(prototype)
  if prototype.minable then
    if prototype.minable.results then
      return prototype.minable.results
    elseif prototype.minable.result then
      return {{ name = prototype.minable.result }}
    end
  end
end

local function initialize()
  for _, character in pairs(data.raw.character) do
    if character.crafting_categories then
      for _, category in pairs(character.crafting_categories) do
        mark_ok(CRAFTING_CATEGORY, category, character.name)
      end
    end
    if character.mining_categories then
      for _, category in pairs(character.mining_categories) do
        mark_ok(RESOURCE_CATEGORY, category, character.name)
      end
    end
  end

  for _, tree in pairs(data.raw.tree) do
    if tree.autoplace and tree.minable then
      mark_ok(ITEM, tree.minable.result, tree.name)
    end
  end

  for _, recipe in pairs(data.raw.recipe) do
    if (recipe.enabled == nil
      and (not recipe.normal or recipe.normal.enabled == nil)
      and (not recipe.expensive or recipe.expensive.enabled == nil))
    or recipe.enabled == true then
      mark_ok(RECIPE, recipe.name, "being initially enabled")
    end
  end
end

local function can_craft(recipe)
  if not is_ok(CRAFTING_CATEGORY, recipe.category or "crafting") then
    if debug[recipe.name] then
      log("recipe "..recipe.name.." inaccessible due to inaccessible crafting category "..recipe.category)
    end
    return false
  end

  local ingredients =
    (type(recipe.normal) == "table" and recipe.normal.ingredients) or
    (type(recipe.expensive) == "table" and recipe.expensive.ingredients) or
    recipe.ingredients or
    {}
  for _, ingredient in pairs(ingredients) do
    local proto_type = ingredient.type == "fluid" and FLUID or ITEM
    local name = ingredient.name or ingredient[1]
    if not is_ok(proto_type, name) then
      if debug[recipe.name] then
        log("recipe "..recipe.name.." inaccessible due to inaccessible ingredient "..name)
      end
      return false
    end
  end

  return true
end

local function unlock_boilable()
  for name in pairs(ok[ENTITY] or {}) do
    local entity = entity_prototype(name)
    if entity.type == "boiler" then
      if is_ok(FLUID, entity.fluid_box.filter) then
        mark_ok(FLUID, entity.output_fluid_box.filter, name)
      end
    end
  end
end

local function unlock_categories()
  if not ok[ENTITY] then return end
  for name in pairs(ok[ENTITY]) do
    local entity = entity_prototype(name)
    if entity then
      for _, category in pairs(entity.crafting_categories or {}) do
        mark_ok(CRAFTING_CATEGORY, category, name)
      end
      for _, category in pairs(entity.resource_categories or {}) do
        mark_ok(RESOURCE_CATEGORY, category, name)
      end
    end
  end
end

local function unlock_craftable()
  for name in pairs(ok[RECIPE]) do
    local recipe = data.raw.recipe[name]
    if can_craft(recipe) then
      local results =
        (type(recipe.normal) == "table" and (recipe.normal.results or {{recipe.normal.result}})) or
        (type(recipe.expensive) == "table" and (recipe.expensive.results or {{recipe.expensive.result}})) or
        recipe.results or
        {{recipe.result}}
      for _, result in pairs(results) do
        local proto_type = result.type or ITEM
        local result_name = result.name or result[1]
        mark_ok(proto_type, result_name, recipe.name)
      end
    end
  end
end

local function unlock_minable()
  for _, resource in pairs(data.raw.resource) do
    if resource.autoplace and resource.minable then
      local category = resource.category or "basic-solid"
      local fluid = resource.minable and resource.minable.required_fluid
      if is_ok(RESOURCE_CATEGORY, category) and (not fluid or is_ok(FLUID, fluid)) then
        for _, result in pairs(mining_results(resource)) do
          local proto_type = result.type or ITEM
          mark_ok(proto_type, result.name, category..(fluid and (" and "..fluid) or ""))
        end
      end
    end
  end
end

local function unlock_placeable()
  for name in pairs(ok[ITEM]) do
    local item = item_prototype(name)
    if item.place_result then
      mark_ok(ENTITY, item.place_result, name)
    end
  end
end

local function unlock_pumpable()
  for name in pairs(ok[ENTITY]) do
    local entity = entity_prototype(name)
    if entity.type == "offshore-pump" then
      mark_ok(FLUID, entity.fluid, name)
    end
  end
end

local function unlock_researchable()
  for _, technology in pairs(data.raw.technology) do
    local has_all = true
    for _, prerequisite in pairs(technology.prerequisites or {}) do
      if not is_ok(TECHNOLOGY, prerequisite) then
        if debug[technology.name] then
          log("cannot research "..technology.name.." because "..prerequisite.." is inaccessible")
        end
        has_all = false
      end
    end

    for _, ingredient in pairs(technology.unit.ingredients) do
      local ingredient_name = ingredient.name or ingredient[1]
      if not is_ok(ITEM, ingredient_name) then
        if debug[technology.name] then
          log("cannot research "..technology.name.." because "..ingredient_name.." is inaccessible")
        end
        has_all = false
      end
    end

    if has_all then
      mark_ok(TECHNOLOGY, technology.name, technology.name)
      for _, effect in pairs(technology.effects or {}) do
        if effect.type == "unlock-recipe" then
          mark_ok(RECIPE, effect.recipe, technology.name)
        end
      end
    end
  end
end

local function run_pass()
  log("running pass")
  changed = false
  unlock_boilable()
  unlock_categories()
  unlock_craftable()
  unlock_minable()
  unlock_placeable()
  unlock_pumpable()
  unlock_researchable()
end

local function log_results()
  for _, proto_type in pairs(ENTITY_TYPES) do
    for name, prototype in pairs(data.raw[proto_type]) do
      if not is_ok(ENTITY, name) then
        log("entity "..name.." is inaccessible")
      end
    end
  end
  for _, proto_type in pairs(ITEM_TYPES) do
    for name, prototype in pairs(data.raw[proto_type]) do
      if not is_ok(ITEM, name) then
        log("item "..name.." is inaccessible")
      end
    end
  end
end

initialize()
while changed do
  run_pass()
end
log_results()
