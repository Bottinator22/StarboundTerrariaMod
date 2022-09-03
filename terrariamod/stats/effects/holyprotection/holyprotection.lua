 function init()
    effect.addStatModifierGroup({
        {stat = "protection", amount = config.getParameter("protection", 100)},
        {stat = "grit", amount = config.getParameter("grit", 1.0)}
    })
    
    self.queryDamageSince = 0
 end
 function update(dt)
    local damageNotifications, nextStep = status.damageTakenSince(self.queryDamageSince)
    self.queryDamageSince = nextStep
    if #damageNotifications > 0 then
        effect.expire()
    end
 end
 function uninit()
 end
