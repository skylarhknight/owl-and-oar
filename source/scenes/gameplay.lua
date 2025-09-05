-- gameplay.lua
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

local gfx = playdate.graphics

GameplayScene = {}
GameplayScene.__index = GameplayScene

-- screen & layout
local SCREEN_W, SCREEN_H = 400, 240
local DOCK_X, DOCK_Y = 200, 70          -- player sprite center (tweak to your art)
local OWL_X, OWL_Y = 340, 40   -- adjust to where your owl should sit


----------------------------------------------------------------
-- Fish catalog (starter set) with basic fight traits
----------------------------------------------------------------
local FISH = {
  {name="Bass",          rarity="Common", size={10,18}, strength=0.20, pattern="steady"},
  {name="Carp",          rarity="Common", size={12,22}, strength=0.18, pattern="gentle"},
  {name="Minnow",        rarity="Common", size={2,4},   strength=0.08, pattern="calm"},
  {name="Shrimp",        rarity="Common", size={2,4},   strength=0.04, pattern="calm"},
  {name="Catfish",       rarity="Medium", size={16,30}, strength=0.35, pattern="steady"},
  {name="Trout",         rarity="Medium", size={12,20}, strength=0.30, pattern="jerky"},
  {name="Salmon",        rarity="Medium", size={18,32}, strength=0.32, pattern="bursty"},
  {name="Golden Koi",    rarity="Rare",   size={14,26}, strength=0.45, pattern="rhythm"},
  {name="Ghost Fish",    rarity="Rare",   size={10,18}, strength=0.38, pattern="quick"},
  {name="Flying Fish",   rarity="Rare",   size={8,14},  strength="0.28", pattern="bursty"},
  {name="Boot Fish",     rarity="Common", size={8,8},   strength=0.10, pattern="calm"},
  {name="Can O' Worms",  rarity="Medium", size={4,6},   strength=0.22, pattern="jerky"},
  {name="Pixel Piranha", rarity="Rare",   size={6,9},   strength=0.50, pattern="spiky"},
  {name="Space Jelly",   rarity="Rare",   size={7,12},  strength=0.12, pattern="quick"},
  --{name="Electric Eel",  rarity="Rare",   size={8,14},  strength=0.28, pattern="bursty"},
  {name="Sea Cucumber",  rarity="Rare",   size={4,6},  strength=0.02, pattern="calm"},
  {name="Kraken Jr.",    rarity="Medium", size={5,10},  strength=0.40, pattern="bursty"},
}
local RARITY_WEIGHT = { Common = 0.60, Medium = 0.30, Rare = 0.10 }

-- utils
local function clamp(v, a, b) if v<a then return a elseif v>b then return v end return v end
local function lerp(a,b,t) return a + (b-a)*t end
local function slugify(name)
  return (name:lower():gsub("[^%w]+","_"):gsub("^_+",""):gsub("_+$",""):gsub("_+","_"))
end

local function pickFish()
  -- rarity by weight
  local r = math.random()
  local chosen = (r <= RARITY_WEIGHT.Common) and "Common"
              or (r <= RARITY_WEIGHT.Common + RARITY_WEIGHT.Medium) and "Medium" or "Rare"
  -- pool
  local pool = {}
  for _, f in ipairs(FISH) do if f.rarity == chosen then table.insert(pool, f) end end
  local fish = pool[math.random(#pool)]
  -- size roll
  local minS, maxS = fish.size[1], fish.size[2]
  local sz = math.random(minS, maxS)
  return {
    name     = fish.name,
    rarity   = fish.rarity,
    sizeIn   = sz,
    strength = fish.strength or 0.3,
    pattern  = fish.pattern  or "steady",
    iconSlug = slugify(fish.name),
  }
end

----------------------------------------------------------------
-- Scene
----------------------------------------------------------------
function GameplayScene.new(manager)
  local s = setmetatable({}, GameplayScene)
  s.manager = manager

  -- background
  s.bg = gfx.image.new("images/bg_day")

  -- load all player poses (fallback to images/player.png if missing)
  s.poseImgs = {
    neutral = gfx.image.new("images/player_neutral") or gfx.image.new("images/player"),
    cast    = gfx.image.new("images/player_cast")    or gfx.image.new("images/player"),
    fish    = gfx.image.new("images/player_fish")    or gfx.image.new("images/player"),
    reel    = gfx.image.new("images/player_reel")    or gfx.image.new("images/player"),
  }

  -- player sprite (starts neutral)
  s.player = gfx.sprite.new(s.poseImgs.neutral or gfx.image.new("images/player"))
  s.player:moveTo(DOCK_X, DOCK_Y)
  s.player:setZIndex(10)
  s.player:add()

  -- state
  s.state = "idle"              -- idle | casting | waiting | hooking | reeling | catch_card
  s.power = 0                   -- 0..1
  s.lastCrankPos = playdate.getCrankPosition()
  s.biteTimer = nil
  s.hookWindowTimer = nil

  -- owl (visual bite indicator)
  s.owlImgs = {
    neutral = gfx.image.new("images/owl_neutral") or gfx.image.new("images/owl"),
    alert   = gfx.image.new("images/owl_alert")   or gfx.image.new("images/owl"),
  }

  s.owl = gfx.sprite.new(s.owlImgs.neutral or gfx.image.new("images/owl"))
  s.owl:moveTo(OWL_X, OWL_Y)
  s.owl:setZIndex(25)  -- above player (player is 10)
  s.owl:add()

  -- owl timers
  s.owlAlertTimer = nil

  -- fish / reeling vars
  s.pendingFish = nil
  s.currentFish = nil
  s.fishDistance = 0            -- 1.0 -> 0.0 to land
  s.tension = 0

  -- UI
  s.statusText = nil
  s.catchInfo = nil
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
-- Helpers (pose swap, timers)
----------------------------------------------------------------
function GameplayScene:_setPose(which)
  local img = self.poseImgs[which]
  if img and self.player and self.player.setImage then
    self.player:setImage(img)
  elseif img and self.player then
    -- super-compat fallback: replace sprite if setImage isn't available
    local x, y = self.player.x, self.player.y
    local z = self.player:getZIndex()
    self.player:remove()
    self.player = gfx.sprite.new(img)
    self.player:moveTo(x, y)
    self.player:setZIndex(z or 10)
    self.player:add()
  end
end

function GameplayScene:_setOwlPose(which)
  if not self.owl or not self.owlImgs then return end
  local img = self.owlImgs[which]
  if not img then return end

  if self.owl.setImage then
    self.owl:setImage(img)
  else
    -- Compatibility fallback if setImage isn't available on your SDK:
    local x, y = self.owl.x, self.owl.y
    local z = self.owl:getZIndex()
    self.owl:remove()
    self.owl = gfx.sprite.new(img)
    self.owl:moveTo(x, y)
    self.owl:setZIndex(z or 25)
    self.owl:add()
  end
end

-- Flash alert pose for `ms` milliseconds, then revert to neutral
function GameplayScene:_owlFlashAlert(ms)
  ms = ms or 1000
  self:_setOwlPose("alert")
  if self.owlAlertTimer then self.owlAlertTimer:remove() end
  self.owlAlertTimer = playdate.timer.new(ms, function()
    self:_setOwlPose("neutral")
    self.owlAlertTimer = nil
  end)
end


function GameplayScene:_clearTimers()
  if self.biteTimer then self.biteTimer:remove(); self.biteTimer = nil end
  if self.hookWindowTimer then self.hookWindowTimer:remove(); self.hookWindowTimer = nil end
  if self.owlAlertTimer then self.owlAlertTimer:remove(); self.owlAlertTimer = nil end
end

function GameplayScene:_choosePendingFish()
  self.pendingFish = pickFish()
end

----------------------------------------------------------------
-- State transitions
----------------------------------------------------------------
function GameplayScene:_startCasting()
  self.state = "casting"
  self.power = 0
  self.lastCrankPos = playdate.getCrankPosition()
  self:_setPose("cast")
end

function GameplayScene:_releaseCast()
  -- choose fish; rarer fish usually wait a bit longer
  self:_choosePendingFish()
  local baseMs = math.random(1000, 6000) -- 1–6 s
  local rarityAdd = (self.pendingFish.rarity == "Rare" and 700)
                 or (self.pendingFish.rarity == "Medium" and 300) or 0
  local waitMs = baseMs + rarityAdd

  self.state = "waiting"
  self:_setPose("fish")
  self.biteTimer = playdate.timer.new(waitMs, function() self:_triggerBite() end)
end

function GameplayScene:_triggerBite()
  if self.state ~= "waiting" then return end
  self.state = "hooking"
  self:_owlFlashAlert(1000)
  -- (Pose stays "fish" during the hook window)
  local window = math.random(500, 1000)
  if self.pendingFish.rarity == "Rare" then window = math.floor(window * 0.8) end
  if self.pendingFish.pattern == "quick" then window = math.floor(window * 0.8) end
  self.hookWindowTimer = playdate.timer.new(window, function()
    if self.state == "hooking" then self:_endCast("Missed the hook!") end
  end)
end

function GameplayScene:_hookFish()
  if self.state ~= "hooking" then return end
  self.currentFish = self.pendingFish or pickFish()
  self.pendingFish = nil
  self.fishDistance = 1.0
  self.tension = 0.0
  self.state = "reeling"
  self:_setPose("reel")
end

function GameplayScene:_snapLine()
  self:_endCast("Line snapped!")
end

-- ends a cast, back to idle (miss, snap, or cancel)
function GameplayScene:_endCast(msg)
  self.state = "idle"
  self:_clearTimers()
  self.pendingFish = nil
  self.currentFish = nil
  self:_setPose("neutral")
  self:_setOwlPose("neutral")
  if msg then
    self.statusText = msg
    playdate.timer.new(1000, function() self.statusText = nil end)
  end
end

function GameplayScene:_finishCatch()
  self:_clearTimers()
  self.catchInfo = self.currentFish or pickFish()
  self.currentFish = nil
  self.state = "catch_card"
  -- (Keep "reel" pose during the card; switch to neutral when it closes)
  self.catchCardTimer = playdate.timer.new(1600, function()
    if self.state == "catch_card" then self:_closeCatchCard() end
  end)
end

function GameplayScene:_closeCatchCard()
  if self.catchCardTimer then self.catchCardTimer:remove(); self.catchCardTimer = nil end
  self.catchInfo = nil
  self.state = "idle"
  self:_setPose("neutral")
end

----------------------------------------------------------------
-- Icon loader (24x24 fit)
----------------------------------------------------------------
function GameplayScene:_getIconBySlug(slug, box)
  box = box or 24
  if not slug or slug == "" then return nil end
  self.iconCache = self.iconCache or {}
  local key = slug .. "#" .. tostring(box)
  if self.iconCache[key] ~= nil then return self.iconCache[key] end

  local candidates = {
    "images/fish/icons/" .. slug,  -- preferred tiny icon
    "images/fish/"       .. slug,  -- fallback big art
  }

  local img = nil
  for _, path in ipairs(candidates) do
    img = gfx.image.new(path)  -- tries .png
    if img then break end
  end

  if not img then
    img = gfx.image.new("images/fish/icons/default") or gfx.image.new("images/fish/default")
    if not img then
      print("Fish icon not found for slug: " .. slug)
      return nil
    end
  end

  -- scale to fit (never upscale)
  local iw, ih = img:getSize()
  local scale = math.min(box / iw, box / ih, 1)
  if scale < 1 and img.scaledImage then
    img = img:scaledImage(scale)
  end

  self.iconCache[key] = img
  return img
end

----------------------------------------------------------------
-- Input
----------------------------------------------------------------
function GameplayScene:AButtonDown()
  if self.state == "idle" then
    self:_startCasting()
  elseif self.state == "casting" then
    self:_releaseCast()
  elseif self.state == "catch_card" then
    self:_closeCatchCard()
  end
end

function GameplayScene:BButtonDown()
  if self.state == "hooking" then
    if self.hookWindowTimer then self.hookWindowTimer:remove(); self.hookWindowTimer = nil end
    self:_hookFish()
  elseif self.state == "waiting" then
    self:_endCast("Reeled back empty.")
  end
end

-- crank used for power (casting) and reeling (reeling)
function GameplayScene:cranked(change, acceleratedChange)
  if self.state == "casting" then
    local delta = math.abs(change) / 180    -- tune sensitivity
    self.power = math.min(1, self.power + delta)

  elseif self.state == "reeling" then
    local forward  = math.max(0,  change) / 90
    local backward = math.max(0, -change) / 90

    -- progress and slack
    self.fishDistance = math.max(0, math.min(1, self.fishDistance - forward * 0.03 + backward * 0.015))

    -- tension: rises with reel speed & fish strength; decays over time and with slack
    local accel = math.abs(acceleratedChange) / 720
    local fishStrength = (self.currentFish and self.currentFish.strength) or 0.3
    local pullFactor = (forward > 0) and (forward * fishStrength) or 0
    self.tension = math.max(0, math.min(1, self.tension + pullFactor * 0.25 + accel * 0.15 - 0.02 - backward * 0.10))

    if self.tension >= 1 then
      self:_snapLine(); return
    end
    if self.fishDistance <= 0 then
      self:_finishCatch(); return
    end
  end
end

----------------------------------------------------------------
-- Update / Draw
----------------------------------------------------------------
function GameplayScene:update()
  -- HUD overlays
  if self.state == "casting" then
    self:_drawPowerBar()
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
  gfx.setColor(gfx.kColorWhite); gfx.fillRect(x-2, y-2, w+4, h+4)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(x-2, y-2, w+4, h+4)
  gfx.fillRect(x, y, math.floor(w * self.power), h)
  gfx.drawTextAligned("Power", x + w/2, y - 12, kTextAlignment.center)
end

function GameplayScene:_drawTensionAndDistance()
  local x, y = 8, 8
  gfx.drawText("Tension", x, y)
  gfx.drawRect(x, y+12, 80, 8)
  gfx.fillRect(x, y+12, math.floor(80 * self.tension), 8)

  gfx.drawText("Reel", x, y+28)
  gfx.drawRect(x, y+40, 80, 8)
  gfx.fillRect(x, y+40, math.floor(80 * (1.0 - self.fishDistance)), 8)
end

-- 120×80 centered catch card with icon + text
function GameplayScene:_drawCatchCard(info)
  local w, h = 120, 80
  local x = (SCREEN_W - w) // 2
  local y = (SCREEN_H - h) // 2

  gfx.setColor(gfx.kColorWhite); gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(x, y, w, h)

  local cx = x + w // 2
  gfx.drawTextAligned("Caught!", cx, y + 6, kTextAlignment.center)
  gfx.drawLine(x+8, y+20, x+w-8, y+20)

  -- icon (left) + text (right)
  local iconSize, iconX, iconY = 24, x + 10, y + 28
  local icon = self:_getIconBySlug(info.iconSlug, iconSize)

  gfx.setClipRect(iconX, iconY, iconSize, iconSize)
  if icon then
    local iw, ih = icon:getSize()
    local drawX = iconX + math.floor((iconSize - iw) / 2)
    local drawY = iconY + math.floor((iconSize - ih) / 2)
    icon:draw(drawX, drawY)
  end
  gfx.clearClipRect()
  gfx.drawRect(iconX, iconY, iconSize, iconSize)

  local tx = iconX + iconSize + 8
  gfx.drawTextAligned(info.name, tx + 40, y + 28, kTextAlignment.center)
  gfx.drawTextAligned("Rarity: " .. info.rarity, tx + 40, y + 42, kTextAlignment.center)
  gfx.drawTextAligned("Size: " .. tostring(info.sizeIn) .. " in", tx + 40, y + 56, kTextAlignment.center)

  gfx.drawTextAligned("A to close", cx, y + h + 6, kTextAlignment.center)
end