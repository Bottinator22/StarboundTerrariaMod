function init()
    self.cooldown = 0
    self.queryDamageSince = 0
end

function update(dt)
    if status.statusProperty("hallowedlegs") then
        if status.statusProperty("hallowedhead") then
            -- Set bonus effect
            self.cooldown = self.cooldown - dt
            local damageNotifications, nextStep = status.inflictedDamageSince(self.queryDamageSince)
            self.queryDamageSince = nextStep
            if self.cooldown < 0 then
                if #damageNotifications > 0 then
                    status.addEphemeralEffect("holyprotection")
                    self.cooldown = 30
                end
            end
        end
    end
end

function uninit()

end
