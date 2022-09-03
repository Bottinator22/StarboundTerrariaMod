require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"
require "/scripts/companions/capturable.lua"

local initialized
local targetId
local queryRange
local keepTargetInRange
local targets
local outOfSight
local targetCheckTPS
local targetCheckTime
local secondPhase = false
local musicRange = 200
local headId
local jumpTimer = 100
local leftHandId
local rightHandId
local wasOnGround = true
function ownerId()
    if capturable.ownerUuid() then
        local playerIds = world.players()
        table.sort(playerIds, function(a)
      return world.entityUniqueId(a) == capturable.ownerUuid() end)
        return playerIds[1]
    else
        return nil
    end
end
-- Engine callback - called on initialization of entity
function init()
    self.pathing = {}
    self.shouldDie = true
    fireTime = math.random(0, 250)
initialized = false
  targetId = nil
  queryRange = 100
  keepTargetInRange = 250
  targets = {}
targetCheckTPS = 10
targetCheckTime = 1
monster.setAggressive(true)

  message.setHandler("damageTeam", function(_,_,team)
        monster.setDamageTeam(team)
  end)
  self.notifications = {}
  storage.spawnTime = world.time()
  if storage.spawnPosition == nil or config.getParameter("wasRelocated", false) then
    local position = mcontroller.position()
    local groundSpawnPosition
    if mcontroller.baseParameters().gravityEnabled then
      groundSpawnPosition = findGroundPosition(position, -20, 3)
    end
    storage.spawnPosition = groundSpawnPosition or position
  end

  self.collisionPoly = mcontroller.collisionPoly()

  if animator.hasSound("deathPuff") then
    monster.setDeathSound("deathPuff")
  end
  if config.getParameter("deathParticles") then
    monster.setDeathParticleBurst(config.getParameter("deathParticles"))
  end

  script.setUpdateDelta(config.getParameter("initialScriptDelta", 1))
  mcontroller.setAutoClearControls(false)

  animator.setGlobalTag("flipX", "")

  self.debug = true

  message.setHandler("notify", function(_,_,notification)
      return notify(notification)
    end)
  message.setHandler("despawn", function()
    end)

  self.forceRegions = ControlMap:new(config.getParameter("forceRegions", {}))
  self.damageSources = ControlMap:new(config.getParameter("damageSources", {}))
  self.touchDamageEnabled = false
  
  monster.setDamageBar("None")
  capturable.init()
  
  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", {})
  
  mcontroller.controlFace(1)
  local level = monster.level()
  if ownerId() then
      level = 7
  end
  headId = world.spawnMonster("golemhead", mcontroller.position(), {ownerId=entity.id(),level=level, damageTeam=entity.damageTeam().team, damageTeamType = entity.damageTeam().type})
  leftHandId = world.spawnMonster("golemfist", mcontroller.position(), {ownerId=entity.id(),headId=headId,level=level, anchorPos={-4.25, -0.5}, fistType="left", damageTeam=entity.damageTeam().team, damageTeamType = entity.damageTeam().type})
  rightHandId = world.spawnMonster("golemfist", mcontroller.position(), {ownerId=entity.id(),headId=headId,level=level, anchorPos={4.25, -0.5}, damageTeam=entity.damageTeam().team, damageTeamType = entity.damageTeam().type})
end
function targeting()
    if targetId then
        if not world.entityExists(targetId) then
            targetId = nil
        end
    end
    targetCheckTime = targetCheckTime + 1  
    if targetCheckTime >= targetCheckTPS - 1 then
        if #targets == 0 then
            local newTargets = world.entityQuery(mcontroller.position(), queryRange, {includedTypes = {"player","npc","monster"}})
            table.sort(newTargets, function(a, b)
                return world.magnitude(world.entityPosition(a), mcontroller.position()) < world.magnitude(world.entityPosition(b), mcontroller.position())
            end)
            for _,entityId in pairs(newTargets) do
                if entity.isValidTarget(entityId) then
                    table.insert(targets, entityId)
                end
            end
        end
        repeat
            targetId = targets[1]
            local testTargetId = targetId
            if testTargetId == nil then break end
            -- {math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}
            if not world.entityExists(testTargetId) or world.magnitude(world.entityPosition(testTargetId), mcontroller.position()) > keepTargetInRange then
                table.remove(targets, 1)
                testTargetId = nil
            end
            if not testTargetId or not entity.isValidTarget(testTargetId) then
                table.remove(targets, 1)
                testTargetId = nil
            end
            targetId = testTargetId
        until #targets <= 0 or targetId
        targetCheckTime = 0
    end
end
function doSecondPhase()
    secondPhase = true
    monster.setDamageBar("Special")
    status.clearPersistentEffects("invuln")
end
function update(dt)
  capturable.update(dt)
  monster.setDamageOnTouch(true)
  targeting()
  mcontroller.clearControls()
  if not wasOnGround and mcontroller.onGround() then
      animator.playSound("stomp")
  end
  wasOnGround = mcontroller.onGround()
  if targetId then
      handleJumping(world.entityPosition(targetId))
  elseif ownerId() then
      local ownerPos = world.entityPosition(ownerId())
      if world.magnitude(ownerPos, mcontroller.position()) > 8 then
          local telePos = vec2.add(ownerPos, {0, 8})
          if world.magnitude(ownerPos, mcontroller.position()) > 50 and not world.polyCollision(mcontroller.collisionPoly(), telePos, {"Block", "Dynamic", "Slippery"}) then
              mcontroller.setPosition(telePos)
              mcontroller.setVelocity({0, 0})
          else
            handleJumping(ownerPos)
          end
      end
  end
  if secondPhase then
      
  else
      status.setPersistentEffects("invuln", {{stat="invulnerable",amount=1}})
  end
  -- player music
  local players = world.playerQuery(mcontroller.position(), musicRange)
  for _,entityId in pairs(players) do
      world.sendEntityMessage(entityId, "terraMusic", {id=entity.id(),file=config.getParameter("music"),expireType="entityDistance",entityID=entity.id(),entityDis=musicRange,priority=monster.level() + 10})
  end
end
function handleJumping(targetPos)
      jumpTimer = jumpTimer + 1
      local leftHandPerc = 0
      if world.entityExists(leftHandId) then
        leftHandPerc = (world.entityHealth(leftHandId)[1] / world.entityHealth(leftHandId)[2])
      end
      local rightHandPerc = 0
      if world.entityExists(rightHandId) then
        rightHandPerc = (world.entityHealth(rightHandId)[1] / world.entityHealth(rightHandId)[2])
      end
      if jumpTimer > 60 + 75 * (status.resourcePercentage("health") + (world.entityHealth(headId)[1] / world.entityHealth(headId)[2]) + (leftHandPerc + rightHandPerc) / 2) then
          jumpTimer = 1
      end
      local frameMult = 5
      animator.setGlobalTag("jumpFrame", tostring(math.floor(math.min(math.max(jumpTimer / frameMult, 1), 6))))
      if jumpTimer / frameMult <= 6 then
          animator.setAnimationState("body", "jump")
      else
          animator.setAnimationState("body", "idle")
      end
      if math.floor(jumpTimer / frameMult) == 4 then
          local diff = world.distance(targetPos, mcontroller.position())
          local jumpHVel = 20
          local vel = {0, 0}
          vel[1] = jumpHVel * math.max(math.min(diff[1], 1), -1)
          vel[2] = math.min(math.max(30, diff[2] * 4), 60)
          mcontroller.setVelocity(vel)
      end
      if not mcontroller.onGround() then
          mcontroller.setVelocity(vec2.add(mcontroller.velocity(), math.max(math.min(world.distance(targetPos, mcontroller.position())[1], 0.01), -0.01)))
      end
      if targetPos[2] < mcontroller.yPosition() - 5 then
          mcontroller.controlDown()
      end
      world.debugText("%s\n%s",tostring(jumpTimer),tostring(jumpTimer / frameMult), mcontroller.position(), "green")
end
function interact(args)
end

function shouldDie()
    return (self.shouldDie and status.resource("health") <= 0) or capturable.justCaptured
end

function die()
  if not capturable.justCaptured then
    capturable.die()
  end
end
function setHealth(health)
    lastHealth = health
    status.setResourcePercentage("health", health)
end
