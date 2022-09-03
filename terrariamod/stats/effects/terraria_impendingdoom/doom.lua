
function init()
   world.sendEntityMessage(entity.id(), "queueRadioMessage", "terraria_impendingdoom", 5.0)
end

function update(dt)
end

function uninit()
    if effect.duration() <= 1 then
        world.spawnMonster("moonlord", entity.position(), {level=10})
    end
end
