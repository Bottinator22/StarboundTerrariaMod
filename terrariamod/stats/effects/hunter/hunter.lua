--Made by Silver Sokolova#3576
function init()
  script.setUpdateDelta(120)
  ownTeam = world.entityDamageTeam(entity.id())
  entityId = entity.id()
end

function update(dt)
  local targetlist = world.entityQuery(mcontroller.position(),180)
  for _, value in pairs(targetlist) do
    if value ~= entityId then
      world.sendEntityMessage(value,"applyStatusEffect","novakidglow")
      world.sendEntityMessage(value,"applyStatusEffect",world.entityCanDamage(value,entityId) and "colorred" or "colorgreen")
    end
  end
end