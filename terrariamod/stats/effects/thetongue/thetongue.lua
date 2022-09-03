local pulling 
 function init()
    message.setHandler("move", function(_, _, pos)
      mcontroller.setPosition(pos)
      pulling = true -- mouth is pulling this target in
    end)
 end
 function update(dt)
     if pulling then
        mcontroller.setVelocity({0, 0})
        -- makes pulling in easier
        mcontroller.controlParameters({
            gravityMultiplier = 0
        })
     end
 end
 function uninit()
 end
