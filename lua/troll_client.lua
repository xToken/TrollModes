-- lua\troll_client.lua
-- - Dragon

-- Main
local kTrollMode = false
local kScareMode = false
local kMarioMode = false
local kTrollingCheckFunctions = { }
local kShadeSpawnChance = 0.5

local function CleanupTrollModes()
	StopTrollingMusic()
	CleanupShades(true)
end

local function ValidateTrollModesAllowed()
	local gameInfo = GetGameInfoEntity()
	if gameInfo and gameInfo.GetNSLConfig then
		if gameInfo:GetNSLConfig() == kNSLPluginConfigs.OFFICIAL then
			return false
		end
	end
	for i = 1, #kTrollingCheckFunctions do
		if not kTrollingCheckFunctions[i]() then
			return false
		end
	end
	-- Other Possible checks?
	return true
end

-- Call this with a function to have it checked if troll modes should be blocked.
function RegisterTrollModeBlocker(method)
	if type(method) == "function" then
		table.insert(kTrollingCheckFunctions, method)
		-- Turn all off to be sure.
		kTrollMode = false
		kScareMode = false
		kMarioMode = false
		CleanupTrollModes()
	else
		Shared.Message("Attempted to register non-function argument for Troll mode blocker.")
		Shared.Message(Script.CallStack())
	end
end

local function ToggleTrollMode(client)
	kTrollMode = not kTrollMode and ValidateTrollModesAllowed()
	if not kTrollMode then
		StopTrollingMusic()
		CleanupShades(true)
	end
	Shared.Message("Trolling mode: " .. ConditionalValue(kTrollMode, "activated", "deactivated"))
end

Event.Hook("Console_trollmode", ToggleTrollMode)

local function ToggleScareMode(client)
	kScareMode = not kScareMode and ValidateTrollModesAllowed()
	Shared.Message("Scary mode: " .. ConditionalValue(kScareMode, "activated", "deactivated"))
end

Event.Hook("Console_scaremode", ToggleScareMode)

local function ToggleMarioMode(client)
	kMarioMode = not kMarioMode and ValidateTrollModesAllowed()
	Shared.Message("Mario mode: " .. ConditionalValue(kMarioMode, "activated", "deactivated"))
end

Event.Hook("Console_mariomode", ToggleMarioMode)

-- Hooks
local oldSharedPlayPrivateSound = Shared.PlayPrivateSound
local oldSharedPlaySound = Shared.PlaySound
local oldSharedStopSound = Shared.StopSound
local oldSharedPlayWorldSound = Shared.PlayWorldSound
local oldClientCreateSoundEffect = Client.CreateSoundEffect
local oldClientPlayMusic = Client.PlayMusic

local function CheckForSoundTrolls(soundEffectName, volume)
	if kTrollMode then
		return CheckForHornTrolling(soundEffectName, volume)
	end
	if kMarioMode then
		return CheckForMarioTrolling(soundEffectName, volume)
	end
	return soundEffectName, volume
end

local function CheckForAttackTrolls(player)
	CheckForTrollingCinematic(player)
end

local function CheckForKillTrolls(player)
	CheckForTrollingMusic(player)
end

function Shared.PlayPrivateSound(forPlayer, soundEffectName, parent, volume, origin)
	soundEffectName, volume = CheckForSoundTrolls(soundEffectName, volume or 1)
	oldSharedPlayPrivateSound(forPlayer, soundEffectName, parent, volume, origin)
end

function Shared.PlaySound(onEntity, soundEffectName, volume)
	soundEffectName, volume = CheckForSoundTrolls(soundEffectName, volume or 1)
	oldSharedPlaySound(onEntity, soundEffectName, volume)
end

function Shared.StopSound(onEntity, soundEffectName)
	local v
	soundEffectName, v = CheckForSoundTrolls(soundEffectName, 1)
	oldSharedStopSound(onEntity, soundEffectName)
end

function Shared.PlayWorldSound(onEntity, soundEffectName, parent, atOrigin, volume)
	soundEffectName, volume = CheckForSoundTrolls(soundEffectName, volume or 1)
	oldSharedPlayWorldSound(onEntity, soundEffectName, parent, atOrigin, volume)
end

function Client.CreateSoundEffect(assetIndex)
	-- find old name, translate, get new asset?
	local effectName, v = CheckForSoundTrolls(Shared.GetSoundName(assetIndex), 1)
	assetIndex = Shared.GetSoundIndex(effectName)
	return oldClientCreateSoundEffect(assetIndex)
end

local originalPlayerPrimaryAttack
originalPlayerPrimaryAttack = Class_ReplaceMethod("Player", "PrimaryAttack",
	function(self)
		originalPlayerPrimaryAttack(self)
		CheckForAttackTrolls(self)
	end
)

local function DetectPlayerKill()
	local originalGUIDeathMessagesAddMessage
	originalGUIDeathMessagesAddMessage = Class_ReplaceMethod("GUIDeathMessages", "AddMessage",
		function(self, killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer)
			originalGUIDeathMessagesAddMessage(self, killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer)
			local player = Client.GetLocalPlayer()
			if player:GetName() == killerName then
				CheckForKillTrolls(player)
			end
		end
	)
end

local function DetectGUIDeathMessagesInit(name, script)
	if name == "GUIDeathMessages" then
		DetectPlayerKill()
	end
end

ClientUI.AddScriptCreationEventListener(DetectGUIDeathMessagesInit)

-- Trolling Util Funcs
local kBigUpVector = Vector(0, 1000, 0)
local function CastToGround(pointToCheck, height, radius, filterEntity)

    local filter = EntityFilterOne(filterEntity)
    
    local extents = Vector(radius, height * 0.5, radius)
    trace = Shared.TraceBox( extents, pointToCheck, pointToCheck - kBigUpVector, CollisionRep.Move, PhysicsMask.All, filter)
    
    if trace.fraction ~= 1 then
    
        -- Check the start point is not colliding.
        if not Shared.CollideBox(extents, trace.endPoint, CollisionRep.Move, PhysicsMask.All, filter) then
            return trace.endPoint - Vector(0, height * 0.5, 0)
        end
        
    end
    
    return nil
    
end

local function GetRandomPoint(origin, minRange, maxRange, player)
	local randomRange = minRange + math.random() * (maxRange - minRange)
    local randomRadians = math.random() * math.pi * 2
    local randomHeight = 3
    local randomPoint = Vector(origin.x + randomRange * math.cos(randomRadians),
                               origin.y + randomHeight,
                               origin.z + randomRange * math.sin(randomRadians))
    
    return CastToGround(randomPoint, 0.1, 0.1, player)
end

local function CheckPlayerHasLOS(player, point)
    local trace = Shared.TraceRay(player:GetEyePos(), point, CollisionRep.Move, PhysicsMask.Movement, EntityFilterAll())
    return trace.fraction == 1
end

-- Shades everywhereeeeeeeee.
local shadeCinematic = PrecacheAsset("cinematics/alien/shade/fake_shade.cinematic")
local shadeSpawnRate = 0
local shadeLastSpawn = 0
local shadeLifetime = 10
local shadeTable = { }

local function ToggleTrollRate(rate)
	if rate and tonumber(rate) then
		shadeSpawnRate = tonumber(rate)
	else
		shadeSpawnRate = 20
	end
	Shared.Message("Shade rate set to: " .. ToString(shadeSpawnRate))
end

Event.Hook("Console_trollrate", ToggleTrollRate)

function CleanupShades(force)
	local t = Shared.GetTime()
	for i = #shadeTable, 1, -1 do
		if shadeTable[i] then
			if (shadeTable[i].t < t or force) then
				if shadeTable[i].c then
					Client.DestroyCinematic(shadeTable[i].c)
					shadeTable[i].c = nil
				end
				shadeTable[i] = nil
			end
		end
	end
end

function CheckForTrollingCinematic(player)
	if kTrollMode then
		if math.random() > kShadeSpawnChance then
			local randomPoint = GetRandomPoint(player:GetOrigin(), 1, 20, player)
			if randomPoint and shadeSpawnRate >= 0 and Shared.GetTime() > shadeLastSpawn + shadeSpawnRate then
				CleanupShades(false)
				local c = { }
				c.c = Client.CreateCinematic(RenderScene.Zone_Default)
				c.c:SetCinematic(shadeCinematic)        
				c.c:SetRepeatStyle(Cinematic.Repeat_None)
				c.c:SetCoords(Coords.GetTranslation(randomPoint))
				shadeLastSpawn = Shared.GetTime()
				c.t = shadeLastSpawn + shadeLifetime
				table.insert(shadeTable, c)
			end
		end
	end
end

-- AirHorns for everything.
local hornSoundEffect = "sound/compmod.fev/compmod/stuff/air_horn"
local hornReplaceSounds =  
{
"sound/NS2.fev/marine/rifle/fire_single",
"sound/NS2.fev/marine/rifle/fire_single_2",
"sound/NS2.fev/marine/rifle/fire_single_3",
"sound/NS2.fev/marine/rifle/fire_14_sec_loop",
"sound/NS2.fev/marine/rifle/fire_loop_2",
"sound/NS2.fev/marine/rifle/fire_loop_3",
"sound/NS2.fev/marine/rifle/fire_loop_1_upgrade_1",
"sound/NS2.fev/marine/rifle/fire_loop_2_upgrade_1",
"sound/NS2.fev/marine/rifle/fire_loop_3_upgrade_1",
"sound/NS2.fev/marine/rifle/fire_loop_1_upgrade_3",
"sound/NS2.fev/marine/rifle/fire_loop_2_upgrade_3",
"sound/NS2.fev/marine/rifle/fire_loop_3_upgrade_3",
"sound/NS2.fev/alien/skulk/bite",
"sound/NS2.fev/alien/lerk/bite",
"sound/NS2.fev/alien/skulk/bite_alt",
"sound/NS2.fev/alien/skulk/parasite",
"sound/NS2.fev/alien/lerk/spikes",
"sound/NS2.fev/alien/fade/swipe",
"sound/NS2.fev/alien/fade/metabolize",
"sound/NS2.fev/alien/onos/gore",
"sound/NS2.fev/marine/pistol/fire",
"sound/NS2.fev/marine/axe/attack",
"sound/NS2.fev/marine/axe/attack_female",
"sound/NS2.fev/marine/shotgun/fire",
"sound/NS2.fev/marine/shotgun/fire_upgrade_1",
"sound/NS2.fev/marine/shotgun/fire_upgrade_3",
"sound/NS2.fev/marine/shotgun/fire_last",
"sound/NS2.fev/marine/rifle/fire_grenade",
"sound/NS2.fev/alien/skulk/jump",
"sound/NS2.fev/alien/gorge/jump",
"sound/NS2.fev/alien/fade/jump",
"sound/NS2.fev/alien/onos/jump",
"sound/NS2.fev/marine/heavy/jump",
"sound/NS2.fev/marine/common/jump",
}

Client.PrecacheLocalSound(hornSoundEffect)

function CheckForHornTrolling(effectname, volume)
	if table.contains(hornReplaceSounds, effectname) then
		return hornSoundEffect, volume
	end
	return effectname, volume
end

-- MLG Music for Kills ofc
local mlgKillMusic = "sound/compmod.fev/compmod/stuff/bgmusic"
local mlgAmbientSound
local mlgDisorientScalar = 4
local mlgDisorientFrames = 350

Client.PrecacheLocalSound(mlgKillMusic)

local function CreateBGMusic()
	mlgAmbientSound = AmbientSound()
	mlgAmbientSound.eventName = mlgKillMusic
	mlgAmbientSound.minFalloff = 999
	mlgAmbientSound.maxFalloff = 1000
	mlgAmbientSound.falloffType = 2
	mlgAmbientSound.positioning = 2
	mlgAmbientSound.volume = 1
	mlgAmbientSound.pitch = 0
end

CreateBGMusic()

function StopTrollingMusic()
	mlgAmbientSound:StopPlaying()
end

function CheckForTrollingMusic(player)
	if kTrollMode then
		mlgAmbientSound:StopPlaying()
		mlgAmbientSound:StartPlaying()
		local disorientCounts = 0
		player:AddTimedCallback(function()
									player.disorientedAmount = math.random() * mlgDisorientScalar
									disorientCounts = disorientCounts + 1
									if disorientCounts > mlgDisorientFrames then
										return false
									end
									return 0
								end, 0)		
	end
end

-- Slenderman watches you sleep
local slendermanMinDistance = 15
local slendermanMaxDistance = 30
local slendermanDestroyDistance = 40
local slendermanVisibleFor = 0.3
local slendermanHiddenFor = 20
local slendermanHeight = 1
local slendermanCoordsUpdate = 0.25
local slendermanLastCoordsUpdate = 0
local slendermanCinematicEffect = PrecacheAsset("cinematics/alien/fake.cinematic")
local slendermanDiscoveredSound = "sound/compmod.fev/compmod/stuff/alert"
local slendermanCinematic
local slendermanPoint = Vector(0,0,0)
local slendermanEyePoint
local slendermanSeenAt = 0
local slendermanHiddenTil = slendermanHiddenFor

Client.PrecacheLocalSound(slendermanDiscoveredSound)

local function UpdateSlenderman(deltaTime)

    if kScareMode then
	
		local player = Client.GetLocalPlayer()
		if not player then
			return
		end
		
		local t = Shared.GetTime()
		
		if slendermanHiddenTil > 0 and slendermanHiddenTil < t then
			-- Time to Stalk
			local point, tries = nil
			tries = 0
			while not point and tries < 10 do
				point = GetRandomPoint(player:GetOrigin(), slendermanMinDistance, slendermanMaxDistance, player)
				tries = tries + 1
			end
			if point then
				if not slendermanCinematic then
					slendermanCinematic = Client.CreateCinematic(RenderScene.Zone_Default)
					slendermanCinematic:SetCinematic(slendermanCinematicEffect)
					slendermanCinematic:SetRepeatStyle(Cinematic.Repeat_Endless)
					slendermanSpawnTime = t
				end
				slendermanCinematic:SetCoords(Coords.GetTranslation(point))
				slendermanCinematic:SetIsVisible(true)
				slendermanPoint = point
				slendermanEyePoint = point
				slendermanEyePoint.y = slendermanEyePoint.y + slendermanHeight
				slendermanHiddenTil = 0
			end
		end
		
		if slendermanHiddenTil == 0 then
		
			if slendermanLastCoordsUpdate + slendermanCoordsUpdate < t then
				slendermanCinematic:SetCoords(Coords.GetLookIn(slendermanPoint, player:GetEyePos()))
				slendermanLastCoordsUpdate = t
			end
			
			local seen = CheckPlayerHasLOS(player, slendermanEyePoint)    
			local outOfRange = ((player:GetOrigin() - slendermanPoint):GetLength() >= slendermanDestroyDistance)
			
			if slendermanSeenAt == 0 and (seen or outOfRange) then
				slendermanSeenAt = t
			end
			
			if slendermanSeenAt + slendermanVisibleFor < t and (seen or outOfRange) then
				if seen then
					-- Play Sound!
					-- oldSharedPlaySound(nil, slendermanDiscoveredSound)
				end
				slendermanHiddenTil = t + slendermanHiddenFor
				slendermanCinematic:SetIsVisible(false)
				slendermanSeenAt = 0
			end
			
		end
		
	end
    
end

Event.Hook("UpdateClient", UpdateSlenderman)

-- MarioMode
local kMarioModeSounds = { }

kMarioModeSounds["sound/NS2.fev/alien/skulk/jump"] = "sound/compmod.fev/compmod/mario/Jumpsmall"
kMarioModeSounds["sound/NS2.fev/alien/gorge/jump"] = "sound/compmod.fev/compmod/mario/Jumpbig"
kMarioModeSounds["sound/NS2.fev/alien/fade/jump"] = "sound/compmod.fev/compmod/mario/Jumpbig"
kMarioModeSounds["sound/NS2.fev/alien/onos/jump"] = "sound/compmod.fev/compmod/mario/Jumpbig"
kMarioModeSounds["sound/NS2.fev/marine/heavy/jump"] = "sound/compmod.fev/compmod/mario/Jumpbig"
kMarioModeSounds["sound/NS2.fev/alien/skulk/jump_good"] = "sound/compmod.fev/compmod/mario/Jumpbig"
kMarioModeSounds["sound/NS2.fev/alien/skulk/jump_best"] = "sound/compmod.fev/compmod/mario/Jumpbig"
kMarioModeSounds["sound/NS2.fev/marine/common/jump"] = "sound/compmod.fev/compmod/mario/Jumpsmall"
kMarioModeSounds["sound/NS2.fev/alien/common/gestate"] = "sound/compmod.fev/compmod/mario/gestation"
kMarioModeSounds["sound/NS2.fev/alien/common/alien_menu/open_menu"] = "sound/compmod.fev/compmod/mario/Buildmenuopen"
kMarioModeSounds["sound/NS2.fev/marine/common/death"] = "sound/compmod.fev/compmod/mario/Marinedeath"
kMarioModeSounds["sound/NS2.fev/marine/common/death_female"] = "sound/compmod.fev/compmod/mario/Marinedeath"
kMarioModeSounds["sound/NS2.fev/marine/common/sprint_start"] = "sound/compmod.fev/compmod/mario/sprint"
kMarioModeSounds["sound/NS2.fev/marine/common/sprint_tired"] = "sound/compmod.fev/compmod/mario/Sprinttired"
kMarioModeSounds["sound/NS2.fev/marine/common/sprint_start_female"] = "sound/compmod.fev/compmod/mario/sprint"
kMarioModeSounds["sound/NS2.fev/marine/common/sprint_tired_female"] = "sound/compmod.fev/compmod/mario/Sprinttired"
kMarioModeSounds["sound/NS2.fev/marine/common/distress_beacon_marine"] = "sound/compmod.fev/compmod/mario/Beacon"
kMarioModeSounds["sound/NS2.fev/marine/commander/scan_com"] = "sound/compmod.fev/compmod/mario/Scan"
kMarioModeSounds["sound/NS2.fev/marine/structures/infantry_portal_player_spawn"] = "sound/compmod.fev/compmod/mario/IPspawn"
kMarioModeSounds["sound/NS2.fev/alien/gorge/spit"] = "sound/compmod.fev/compmod/mario/Spit"
kMarioModeSounds["sound/NS2.fev/alien/fade/swipe_structure"] = "sound/compmod.fev/compmod/mario/Swipe"
kMarioModeSounds["sound/NS2.fev/alien/fade/swipe"] = "sound/compmod.fev/compmod/mario/Swipe"
kMarioModeSounds["sound/NS2.fev/alien/fade/metabolize"] = "sound/compmod.fev/compmod/mario/Resupply"
kMarioModeSounds["sound/NS2.fev/marine/power_node/destroyed_powerdown"] = "sound/compmod.fev/compmod/mario/Powerdown"
kMarioModeSounds["sound/NS2.fev/marine/power_node/fixed_powerup"] = "sound/compmod.fev/compmod/mario/Powerup"
kMarioModeSounds["sound/NS2.fev/marine/structures/phase_gate_teleport_2D"] = "sound/compmod.fev/compmod/mario/Phase"
kMarioModeSounds["sound/NS2.fev/alien/skulk/death"] = "sound/compmod.fev/compmod/mario/Skulkdeath"
kMarioModeSounds["sound/NS2.fev/alien/voiceovers/chuckle"] = "sound/compmod.fev/compmod/mario/Skulktaunt"
kMarioModeSounds["sound/NS2.fev/alien/skulk/taunt"] = "sound/compmod.fev/compmod/mario/Skulktaunt"
kMarioModeSounds["sound/NS2.fev/alien/lerk/taunt"] = "sound/compmod.fev/compmod/mario/Lerktaunt"
kMarioModeSounds["sound/NS2.fev/alien/gorge/taunt"] = "sound/compmod.fev/compmod/mario/Gorgetaunt"
kMarioModeSounds["sound/NS2.fev/alien/fade/taunt"] = "sound/compmod.fev/compmod/mario/Fadetaunt"
kMarioModeSounds["sound/NS2.fev/alien/onos/taunt"] = "sound/compmod.fev/compmod/mario/Onostaunt"
kMarioModeSounds["sound/NS2.fev/marine/voiceovers/taunt"] = "sound/compmod.fev/compmod/mario/Marinetaunt"
kMarioModeSounds["sound/NS2.fev/alien/lerk/spikes"] = "sound/compmod.fev/compmod/mario/Spikehit"
kMarioModeSounds["sound/NS2.fev/marine/rifle/alt_swing_female"] = "sound/compmod.fev/compmod/mario/Riflebutthit"
kMarioModeSounds["sound/NS2.fev/marine/rifle/alt_swing"] = "sound/compmod.fev/compmod/mario/Riflebutthit"
kMarioModeSounds["sound/NS2.fev/marine/commander/nano_loop"] = "sound/compmod.fev/compmod/mario/Nanoshield"
kMarioModeSounds["sound/NS2.fev/marine/voiceovers/lets_move"] = "sound/compmod.fev/compmod/mario/Marineletsgo"
kMarioModeSounds["sound/NS2.fev/marine/rifle/alt_hit_hard"] = "sound/compmod.fev/compmod/mario/Umbrahit"
kMarioModeSounds["sound/NS2.fev/alien/common/xenocide_start"] = "sound/compmod.fev/compmod/mario/Xenocide"
kMarioModeSounds["sound/NS2.fev/alien/common/xenocide_end"] = ""
kMarioModeSounds["sound/NS2.fev/marine/structures/arc/charge"] = "sound/compmod.fev/compmod/mario/ARCattack"
kMarioModeSounds["sound/NS2.fev/marine/structures/arc/fire"] = ""
kMarioModeSounds["sound/NS2.fev/alien/gorge/bilebomb"] = "sound/compmod.fev/compmod/mario/bilebomb"
kMarioModeSounds["sound/NS2.fev/alien/onos/stomp"] = "sound/compmod.fev/compmod/mario/stomp"
kMarioModeSounds["sound/NS2.fev/marine/heavy/spin_2"] = "sound/compmod.fev/compmod/mario/minigunloop"
kMarioModeSounds["sound/NS2.fev/marine/heavy/spin"] = "sound/compmod.fev/compmod/mario/minigunloop"
kMarioModeSounds["sound/NS2.fev/marine/heavy/spin_up_2"] = "sound/compmod.fev/compmod/mario/miniguncharge"
kMarioModeSounds["sound/NS2.fev/marine/heavy/spin_up"] = "sound/compmod.fev/compmod/mario/miniguncharge"
kMarioModeSounds["sound/NS2.fev/marine/heavy/overheated"] = "sound/compmod.fev/compmod/mario/minigunoverheat"
--kMarioModeSounds["sound/NS2.fev/common/countdown"] = "sound/compmod.fev/compmod/mario/Countdown" - This is played through some wierd engine level server command, cant really tap into it.

for k, v in pairs(kMarioModeSounds) do
	Client.PrecacheLocalSound(v)
end

function CheckForMarioTrolling(effectname, volume)
	if kMarioModeSounds[effectname] then
		return kMarioModeSounds[effectname], volume
	end
	return effectname, volume
end