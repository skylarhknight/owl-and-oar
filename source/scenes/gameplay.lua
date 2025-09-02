local gfx = playdate.graphics

GameplayScene = {}
GameplayScene.__index = GameplayScene

-- screen & layout
local SCREEN_W, SCREEN_H = 400, 240
local DOCK_X, DOCK_Y = 200, 70
local WATER_X_MIN, WATER_X_MAX = 120, 360
local WATER_Y = 180

----------------------------------------------------------------
-- Fish catalog (starter set)
----------------------------------------------------------------
local FISH = {
  {name="Bass",          rarity="Common", size={10, 18}},
  {name="Carp",          rarity="Common", size={12, 22}},
  {name="Minnow",        rarity="Common", size={2, 4}},
  {name="Catfish",       rarity="Medium", size={16, 30}},
  {name="Trout",         rarity="Medium", size={12, 20}},
  {name="Salmon",        rarity="Medium", size={18, 32}},
  {name="Golden Koi",    rarity="Rare",   size={14, 26}},
  {name="Ghost Fish",    rarity="Rare",   size={10, 18}},
  {name="Flying Fish",   rarity="Rare",   size={8, 14}},
  {name="Boot Fish",     rarity="Common", size={8, 8}},
  {name="Can O' Worms",  rarity="Medium", size={4, 6}},
  {name="Pixel Piranha", rarity="Rare",   size={6, 9}},
  {name="Space Jelly",   rarity="Rare",   size={7, 12}},
  {name="Kraken Jr.",    rarity="Medium", size={5, 10}},
}

local RARITY_WEIGHT = { Common = 0.60, Medium = 0.30, Rare = 0.10 }

-- slugify "Golden Koi" -> "golden_koi", "Can O' Worms" -> "can_o_worms"
local function slugify(name)
  return (name:lower()
              :gsub("[^%w]+", "_")
              :gsub("^_+", "")
              :gsub("_+$", "")
              :gsub("_+", "_"))
end

local function pickFish()
  -- pick rarity by weight
  local r = math.random()
  local chosenRarity
  if r <= RARITY_WEIGHT.Common then
    chosenRarity = "Common"
  elseif r <= (RARITY_WEIGHT.Common + RARITY_WEIGHT.Medium) then
    chosenRarity = "Medium"
  else
    chosenRarity = "Rare"
  end

  -- pick a fish of that rarity
  local pool = {}
  for _, f in ipairs(FISH) do
    if f.rarity == chosenRarity then table.insert(pool, f) end
  end
  local fish = pool[math.random(#pool)]

  -- roll a size in inches (whole number for charm)
  local minS, maxS = fish.size[1], fish.size[2]
  local sz = math.random(minS, maxS)

  -- icon path without extension (Playdate will try .png)
  local iconPath = "images/fish/icons/" .. slugify(fish.name)

  return {
    name     = fish.name,
    rarity   = fish.rarity,
    sizeIn   = sz,
    iconPath = iconPath
  }
end

----------------------------------------------------------------
-- Scene
----------------------------------------------------------------
function GameplayScene.new(manager)
  local s = setmetatable({}, GameplayScene)
  s.manager = manager

  -- art
  s.bg = gfx.image.new("images/bg_day")

  s.playerImg = gfx.image.new("images/player")
  s.player = gfx.sprite.new(s.playerImg)
  s.player:moveTo(DOCK_X, DOCK_Y)
  s.player:setZIndex(10)
  s.player:add()

  s.bobberImg = gfx.image.new("images/bobber")
  s.bobber = nil

  -- state
  s.state = "idle"              -- idle | charging | waiting_bite | bite | reeling | catch_card
  s.power = 0
  s.lastCrankPos = playdate.getCrankPosition()
  s.biteTimer = nil
  s.hookWindowTimer = nil

  -- fish / reeling
  s.fishDistance = 0
  s.fishStrength = 0
  s.tension = 0

  -- feedback text (miss/snap)
  s.statusText = nil

  -- catch card
  s.catchInfo = nil             -- {name, rarity, sizeIn, iconPath}
  s.catchCardTimer = nil

  -- icon cache
  s.iconCache = {}

  return s
end

-- background draw callback
local function drawBackground(img)
  gfx.clear()
  if img then img:draw(0, 0) end
end

function GameplayScene:enter()
  gfx.sprite.setBackgroundDrawingCallback(function(x, y, w, h)
    drawBackground(self.bg)
  end)
end

function GameplayScene:leave()
  gfx.sprite.setBackgroundDrawingCallback(nil)
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
function GameplayScene:_spawnBobber(x, y)
  if self.bobber then self.bobber:remove(); self.bobber = nil end
  self.bobber = gfx.sprite.new(self.bobberImg)
  self.bobber:setZIndex(20)
  self.bobber:moveTo(x, y)
  self.bobber:add()
end

function GameplayScene:_removeBobber()
  if self.bobber then self.bobber:remove(); self.bobber = nil end
end

function GameplayScene:_clearTimers()
  if self.biteTimer then self.biteTimer:remove(); self.biteTimer = nil end
  if self.hookWindowTimer then self.hookWindowTimer:remove(); self.hookWindowTimer = nil end
end

function GameplayScene:_startCharging()
  self.state = "charging"
  self.power = 0
  self.lastCrankPos = playdate.getCrankPosition()
end

function GameplayScene:_releaseCast()
  -- map power → bobber landing X
  local x = WATER_X_MIN + (WATER_X_MAX - WATER_X_MIN) * self.power
  local y = WATER_Y - math.floor(6 * self.power)
  self:_spawnBobber(x, y)

  self.state = "waiting_bite"
  self.biteTimer = playdate.timer.new(math.random(1200, 3500), function()
    self:_triggerBite()
  end)
end

function GameplayScene:_triggerBite()
  if self.state ~= "waiting_bite" then return end
  self.state = "bite"

  -- small hook window (800ms)
  self.hookWindowTimer = playdate.timer.new(800, function()
    if self.state == "bite" then
      self:_endCast("Missed the bite!")
    end
  end)
end

function GameplayScene:_hookFish()
  self.fishStrength = math.random(2, 5) / 10.0  -- 0.2..0.5
  self.fishDistance = 1.0
  self.tension = 0.0
  self.state = "reeling"
end

function GameplayScene:_snapLine()
  self:_endCast("Line snapped!")
end

-- ends a cast, returns to idle (used for miss/snap)
function GameplayScene:_endCast(msg)
  self.state = "idle"
  self:_clearTimers()
  self:_removeBobber()
  if msg then
    self.statusText = msg
    playdate.timer.new(1000, function() self.statusText = nil end)
  end
end

-- catch flow: clean up cast, then show catch card
function GameplayScene:_finishCatch()
  -- stop/cleanup cast visuals & timers but do NOT go idle yet
  self:_clearTimers()
  self:_removeBobber()

  -- roll a fish and open the catch card
  self.catchInfo = pickFish()
  self.state = "catch_card"

  -- auto-dismiss after ~1.6s
  self.catchCardTimer = playdate.timer.new(1600, function()
    if self.state == "catch_card" then
      self:_closeCatchCard()
    end
  end)
end

function GameplayScene:_closeCatchCard()
  if self.catchCardTimer then self.catchCardTimer:remove(); self.catchCardTimer = nil end
  self.catchInfo = nil
  self.state = "idle"
end

-- cached icon loader
function GameplayScene:_getIcon(pathNoExt)
  if not pathNoExt then return nil end
  if self.iconCache[pathNoExt] ~= nil then
    return self.iconCache[pathNoExt]
  end
  local img = gfx.image.new(pathNoExt)  -- tries "<path>.png"
  if not img then
    img = gfx.image.new("images/fish/icons/default")
    if not img then
      print("Fish icon missing: " .. pathNoExt .. " (also missing default)")
    end
  end
  self.iconCache[pathNoExt] = img
  return img
end

----------------------------------------------------------------
-- Input
----------------------------------------------------------------
function GameplayScene:AButtonDown()
  if self.state == "idle" then
    self:_startCharging()
  elseif self.state == "charging" then
    self:_releaseCast()
  elseif self.state == "catch_card" then
    self:_closeCatchCard()
  end
end

function GameplayScene:BButtonDown()
  if self.state == "bite" then
    if self.hookWindowTimer then self.hookWindowTimer:remove(); self.hookWindowTimer = nil end
    self:_hookFish()
  end
end

-- crank used for power (charging) and reeling (reeling)
function GameplayScene:cranked(change, acceleratedChange)
  if self.state == "charging" then
    local delta = math.abs(change) / 180  -- tune sensitivity
    self.power = math.min(1.0, self.power + delta)

  elseif self.state == "reeling" then
    local reelSpeed = math.max(0, change) / 90  -- only forward crank reduces distance
    local fight = (math.random() < 0.1) and (math.random() * 0.02) or 0
    self.fishDistance = math.max(0, self.fishDistance - reelSpeed * 0.03 + fight)

    -- tension: rises with crank acceleration + fish strength, decays slowly
    local accel = math.abs(acceleratedChange) / 720
    self.tension = math.max(0, math.min(1, self.tension + accel * 0.2 + self.fishStrength * 0.01 - 0.02))

    if self.tension >= 1 then
      self:_snapLine()
      return
    end

    if self.fishDistance <= 0 then
      self:_finishCatch()
      return
    end
  end
end

----------------------------------------------------------------
-- Update / Draw
----------------------------------------------------------------
function GameplayScene:update()
  -- HUD overlays by state
  if self.state == "charging" then
    self:_drawPowerBar()
  end
  if self.state == "waiting_bite" or self.state == "bite" or self.state == "reeling" then
    self:_drawLineToBobber()
  end
  if self.state == "reeling" then
    self:_drawTensionAndDistance()
  end
  if self.statusText and self.state ~= "catch_card" then
    gfx.drawTextAligned(self.statusText, SCREEN_W/2, 12, kTextAlignment.center)
  end
  if self.state == "catch_card" and self.catchInfo then
    self:_drawCatchCard(self.catchInfo)
  end
end

function GameplayScene:_drawPowerBar()
  local w, h = 140, 10
  local x, y = SCREEN_W/2 - w/2, SCREEN_H - 24
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x-2, y-2, w+4, h+4)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(x-2, y-2, w+4, h+4)
  gfx.fillRect(x, y, math.floor(w * self.power), h)
  gfx.drawTextAligned("Power", x + w/2, y - 12, kTextAlignment.center)
end

function GameplayScene:_drawLineToBobber()
  if not self.bobber then return end
  local bx, by = self.bobber.x, self.bobber.y
  gfx.drawLine(DOCK_X+8, DOCK_Y-20, bx, by)
end

function GameplayScene:_drawTensionAndDistance()
  local x, y = 8, 8
  -- tension bar
  gfx.drawText("Tension", x, y)
  gfx.drawRect(x, y+12, 80, 8)
  gfx.fillRect(x, y+12, math.floor(80 * self.tension), 8)

  -- distance bar
  gfx.drawText("Reel", x, y+28)
  gfx.drawRect(x, y+40, 80, 8)
  gfx.fillRect(x, y+40, math.floor(80 * (1.0 - self.fishDistance)), 8)
end

-- 120×80 centered catch card with name / rarity / size + tiny icon
function GameplayScene:_drawCatchCard(info)
  local w, h = 120, 80
  local x = (SCREEN_W - w) // 2
  local y = (SCREEN_H - h) // 2

  -- panel
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(x, y, w, h)

  -- header
  local cx = x + w // 2
  gfx.drawTextAligned("Caught!", cx, y + 6, kTextAlignment.center)
  gfx.drawLine(x+8, y+20, x+w-8, y+20)

  -- icon (left) + text (right)
  local icon = self:_getIcon(info.iconPath)
  local iconSize = 24
  local iconX = x + 10
  local iconY = y + 28

  if icon then
    local iw, ih = icon:getSize()
    local drawX = iconX + math.max(0, (iconSize - iw) // 2)
    local drawY = iconY + math.max(0, (iconSize - ih) // 2)
    icon:draw(drawX, drawY)
    gfx.drawRect(iconX, iconY, iconSize, iconSize)
  else
    gfx.drawRect(iconX, iconY, iconSize, iconSize)
    gfx.drawText("?", iconX + 10, iconY + 6)
  end

  -- text block
  local tx = iconX + iconSize + 8
  gfx.drawTextAligned(info.name, tx + 40, y + 28, kTextAlignment.center)
  gfx.drawTextAligned("Rarity: " .. info.rarity, tx + 40, y + 42, kTextAlignment.center)
  gfx.drawTextAligned("Size: " .. tostring(info.sizeIn) .. " in", tx + 40, y + 56, kTextAlignment.center)

  -- hint
  gfx.drawTextAligned("A to close", cx, y + h + 6, kTextAlignment.center)
end
