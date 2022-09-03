local tick = 0
local checkID = nil
function update(dt)
    if checkID then
        tick = tick + 1
        if tick > 6 then
            if not world.entityExists(checkID) then
                checkID = nil
            elseif world.entityHealth(checkID)[1] > 0 then
                projectile.die()
            else
                checkID = nil
            end
        end
    end
end
function hit(eid)
    if world.entityHealth(eid)[1] - projectile.power() > 0 then
        projectile.die()
    end
    checkID = eid
    tick = 0
end
