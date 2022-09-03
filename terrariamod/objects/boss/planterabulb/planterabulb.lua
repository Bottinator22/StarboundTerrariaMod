require "/scripts/vec2.lua"

function die()
    local offset = {-50, -50}
    world.spawnMonster("plantera", vec2.add(object.position(), offset), { level = 6})
end
