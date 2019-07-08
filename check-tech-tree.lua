if not data then data = { raw = require("data-raw") } end
if not log then
  log = function(s) print(s) end
end

local function deep_equals(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then
      return false
  elseif ta == "table" then
    for k in pairs(b) do
      if a[k] == nil then
        return false
      end
    end
    for k,v in pairs(a) do
      if not deep_equals(v, b[k]) then
        return false
      end
    end
  elseif a ~= b then
    return false
  end
  return true
end

local function to_set(t)
  local out = {}
  for _, x in pairs(t) do
    out[t] = true
  end
  return out
end

local function uniq(t)
  table.sort(t)
  local w = 1
  for i=1,#t do
    if t[i] ~= t[w] then
      w = w + 1
      t[w] = t[i]
    end
  end
  for i=w+1,#t do
    t[i] = nil
  end
end

local function research_unit_ingredients(tech)
  local out = {}
  for _, ingredient in pairs(tech.unit.ingredients) do
    out[ingredient[1]] = true
  end
  return out
end

local prerequisites_cache = {}
local function research_prerequisites(name)
  local out = prerequisites_cache[name]
  if not out then
    out = {}
    local tech = data.raw.technology[name]
    local prereqs = tech.prerequisites or {}
    for _, direct in pairs(prereqs) do
      out[direct] = true
      for indirect in pairs(research_prerequisites(direct)) do
        out[indirect] = true
      end
    end
    prerequisites_cache[tech.name] = out
  end
  return out
end

for name, tech in pairs(data.raw.technology) do
  local prereqs = tech.prerequisites or {}
  local is_direct = to_set(prereqs)
  for _, prereq in pairs(prereqs) do
    for t in pairs(research_prerequisites(prereq)) do
      if is_direct[t] then
        log("technology "..name.." requires "..t.." that is already indirectly required via "..prereq)
      end
    end
  end
end

for name, tech in pairs(data.raw.technology) do
  local ingredients = research_unit_ingredients(tech)
  for _, prereq in pairs(tech.prerequisites or {}) do
    local parent_ingredients = research_unit_ingredients(data.raw.technology[prereq])
    for ingredient in pairs(parent_ingredients) do
      if not ingredients[ingredient] then
        log("technology "..name.." does not require ingredient "..ingredient.." required by prerequisite "..prereq)
      end
    end
  end
end
