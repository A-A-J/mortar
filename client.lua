local rocketPlacing = false
local mortars = {}
local rocketObject = nil
local placementPreviewObject = nil
local rocketPlacementKeepEntity = false
local rocketCamera = nil
local placementScaleform = nil
local targetingScaleform = nil
local movingMortarNetId = nil
local activeTargetingNetId = nil

local ROCKET_MAX_RANGE_FROM_PLAYER = Config.MaxRangeFromPlayer
local ROCKET_DAMAGE_RADIUS = Config.DamageRadius
local ROCKET_MOVE_SPEED = Config.RocketMoveSpeed
local ROCKET_VERT_SPEED = Config.RocketVertSpeed

local function MortarUiShow()
	SendNUIMessage({ action = "show" })
end

local function MortarUiHide()
	SendNUIMessage({ action = "hide" })
end

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

local function RotationToDirection(rotation)
	local adjustedRotation = {
		x = (math.pi / 180) * rotation.x,
		y = (math.pi / 180) * rotation.y,
		z = (math.pi / 180) * rotation.z,
	}
	local direction = {
		x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
		y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
		z = math.sin(adjustedRotation.x),
	}
	return direction
end

local function RocketButton(ControlButton)
	N_0xe83a3e3557a56640(ControlButton)
end

local function RocketButtonLabel(text)
	PushScaleformMovieFunctionParameterString(text)
end

local function RocketSetupScaleform(scaleformName)
	local scaleform = RequestScaleformMovie(scaleformName)
	while not HasScaleformMovieLoaded(scaleform) do
		Citizen.Wait(0)
	end

	DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 0, 0)

	PushScaleformMovieFunction(scaleform, "CLEAR_ALL")
	PopScaleformMovieFunctionVoid()

	PushScaleformMovieFunction(scaleform, "SET_CLEAR_SPACE")
	PushScaleformMovieFunctionParameterInt(200)
	PopScaleformMovieFunctionVoid()

	PushScaleformMovieFunction(scaleform, "SET_DATA_SLOT")
	PushScaleformMovieFunctionParameterInt(0)
	RocketButton(GetControlInstructionalButton(2, 152, true))
	RocketButtonLabel("Cancel")
	PopScaleformMovieFunctionVoid()

	PushScaleformMovieFunction(scaleform, "SET_DATA_SLOT")
	PushScaleformMovieFunctionParameterInt(1)
	RocketButton(GetControlInstructionalButton(2, 153, true))
	RocketButtonLabel("Place object")
	PopScaleformMovieFunctionVoid()

	PushScaleformMovieFunction(scaleform, "SET_DATA_SLOT")
	PushScaleformMovieFunctionParameterInt(2)
	RocketButton(GetControlInstructionalButton(2, 190, true))
	RocketButton(GetControlInstructionalButton(2, 189, true))
	RocketButtonLabel("Rotate object")
	PopScaleformMovieFunctionVoid()

	PushScaleformMovieFunction(scaleform, "DRAW_INSTRUCTIONAL_BUTTONS")
	PopScaleformMovieFunctionVoid()

	PushScaleformMovieFunction(scaleform, "SET_BACKGROUND_COLOUR")
	PushScaleformMovieFunctionParameterInt(0)
	PushScaleformMovieFunctionParameterInt(0)
	PushScaleformMovieFunctionParameterInt(0)
	PushScaleformMovieFunctionParameterInt(80)
	PopScaleformMovieFunctionVoid()

	return scaleform
end

local function RocketTargetingCameraScaleform(scaleformName)
	local scaleform = RequestScaleformMovie(scaleformName)
	while not HasScaleformMovieLoaded(scaleform) do
		Citizen.Wait(0)
	end
	DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 0, 0)
	PushScaleformMovieFunction(scaleform, "CLEAR_ALL")
	PopScaleformMovieFunctionVoid()
	PushScaleformMovieFunction(scaleform, "SET_CLEAR_SPACE")
	PushScaleformMovieFunctionParameterInt(200)
	PopScaleformMovieFunctionVoid()

	local slot = 0
	local function addRow(buttons, msg)
		PushScaleformMovieFunction(scaleform, "SET_DATA_SLOT")
		PushScaleformMovieFunctionParameterInt(slot)
		for i = 1, #buttons do
			RocketButton(GetControlInstructionalButton(2, buttons[i], true))
		end
		RocketButtonLabel(msg)
		PopScaleformMovieFunctionVoid()
		slot = slot + 1
	end
	addRow({ 172 }, "Forward")
	addRow({ 173 }, "Back")
	addRow({ 44 }, "Up")
	addRow({ 47 }, "Down")
	addRow({ 201 }, "Target")
	addRow({ 202 }, "Cancel")

	PushScaleformMovieFunction(scaleform, "DRAW_INSTRUCTIONAL_BUTTONS")
	PopScaleformMovieFunctionVoid()
	PushScaleformMovieFunction(scaleform, "SET_BACKGROUND_COLOUR")
	PushScaleformMovieFunctionParameterInt(0)
	PushScaleformMovieFunctionParameterInt(0)
	PushScaleformMovieFunctionParameterInt(0)
	PushScaleformMovieFunctionParameterInt(80)
	PopScaleformMovieFunctionVoid()
	return scaleform
end

local function RayCastGamePlayCamera(distance)
	local cameraRotation = GetGameplayCamRot()
	local cameraCoord = GetGameplayCamCoord()
	local direction = RotationToDirection(cameraRotation)
	local destination = {
		x = cameraCoord.x + direction.x * distance,
		y = cameraCoord.y + direction.y * distance,
		z = cameraCoord.z + direction.z * distance,
	}
	local a, b, c, d, e = GetShapeTestResult(StartShapeTestSweptSphere(cameraCoord.x, cameraCoord.y, cameraCoord.z, destination.x, destination.y, destination.z, 0.2, 339, PlayerPedId(), 4))
	return b, c, e
end

local function mortarClearStrikeVisual(netId)
	netId = tonumber(netId)
	if not netId or not mortars[netId] then
		return
	end
	local m = mortars[netId]
	if m.blip and DoesBlipExist(m.blip) then
		RemoveBlip(m.blip)
	end
	m.blip = nil
	m.targetCoords = nil
end

function GetCamForwardVector(cam)
	local rot = GetCamRot(cam, 2)
	local yaw = math.rad(rot.z)
	return vector3(-math.sin(yaw), math.cos(yaw), 0.0)
end

local function RocketClampCamToPlayerRange(camPos, playerXY, maxRange)
	local dx = camPos.x - playerXY.x
	local dy = camPos.y - playerXY.y
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist <= maxRange or dist < 0.001 then
		return camPos
	end
	local scale = maxRange / dist
	return vector3(playerXY.x + dx * scale, playerXY.y + dy * scale, camPos.z)
end

local function WaitForNetworkedEntity(netId, timeoutMs)
	local limit = GetGameTimer() + (timeoutMs or 10000)
	local ent = 0
	while GetGameTimer() < limit do
		ent = NetworkGetEntityFromNetworkId(netId)
		if ent ~= 0 and DoesEntityExist(ent) then
			return ent
		end
		Wait(0)
	end
	return 0
end

local function RocketStartTargetingCamera()
	if not rocketObject or not DoesEntityExist(rocketObject) then
		return
	end
	local ped = PlayerPedId()
	local objectCoords = GetEntityCoords(rocketObject)
	local playerCoords = GetEntityCoords(ped)
	local playerXY = vector3(playerCoords.x, playerCoords.y, 0.0)

	local lift = Config.StrikeCameraHeightAboveAnchor or 60.0
	local minZ = 0.0
	local maxZ = 250.0

	local off = Config.StrikeCameraAnchorOffset
	local anchorWorld
	if off and (off.x * off.x + off.y * off.y + off.z * off.z) > 0.0001 then
		anchorWorld = GetOffsetFromEntityInWorldCoords(rocketObject, off.x, off.y, off.z)
	else
		anchorWorld = objectCoords
	end
	local baseZ = anchorWorld.z

	local pathDelta = Config.StrikeCameraStrikePathDeltaLocal
	local axisX, axisY = 0.0, 1.0
	local initYaw = 0.0
	if pathDelta and (pathDelta.x * pathDelta.x + pathDelta.y * pathDelta.y) > 1e-8 then
		local rightVector, forwardVector, _, _ = GetEntityMatrix(rocketObject)
		local wx = rightVector.x * pathDelta.x + forwardVector.x * pathDelta.y
		local wy = rightVector.y * pathDelta.x + forwardVector.y * pathDelta.y
		local len = math.sqrt(wx * wx + wy * wy)
		if len > 1e-6 then
			axisX, axisY = wx / len, wy / len
			initYaw = math.atan(-axisX, axisY) * (180.0 / math.pi)
		end
	else
		local f = GetEntityForwardVector(rocketObject)
		local fl = math.sqrt(f.x * f.x + f.y * f.y)
		if fl > 1e-6 then
			axisX, axisY = f.x / fl, f.y / fl
			initYaw = math.atan(-axisX, axisY) * (180.0 / math.pi)
		end
	end

	local yawOffDeg = tonumber(Config.StrikeCameraStrikePathYawOffsetDeg) or 0.0
	if math.abs(yawOffDeg) > 1e-6 then
		local rad = yawOffDeg * (math.pi / 180.0)
		local c, s = math.cos(rad), math.sin(rad)
		local ax = axisX * c - axisY * s
		local ay = axisX * s + axisY * c
		axisX, axisY = ax, ay
		initYaw = math.atan(-axisX, axisY) * (180.0 / math.pi)
	end

	local lineOrigin = vector3(anchorWorld.x, anchorWorld.y, 0.0)

	local function projectCamOntoStrikeLine(pos)
		local vx, vy = pos.x - lineOrigin.x, pos.y - lineOrigin.y
		local s = vx * axisX + vy * axisY
		if s < 0.0 then
			s = 0.0
		end
		return vector3(lineOrigin.x + axisX * s, lineOrigin.y + axisY * s, pos.z)
	end

	local point2World = nil
	if off and pathDelta and (pathDelta.x * pathDelta.x + pathDelta.y * pathDelta.y + pathDelta.z * pathDelta.z) > 1e-10 then
		point2World = GetOffsetFromEntityInWorldCoords(
			rocketObject,
			off.x + pathDelta.x,
			off.y + pathDelta.y,
			off.z + pathDelta.z
		)
		if math.abs(yawOffDeg) > 1e-6 then
			local dx = point2World.x - anchorWorld.x
			local dy = point2World.y - anchorWorld.y
			local dz = point2World.z - anchorWorld.z
			local rad = yawOffDeg * (math.pi / 180.0)
			local c, s = math.cos(rad), math.sin(rad)
			local rx = dx * c - dy * s
			local ry = dx * s + dy * c
			point2World = vector3(anchorWorld.x + rx, anchorWorld.y + ry, anchorWorld.z + dz)
		end
	end

	if rocketCamera ~= nil then
		DestroyCam(rocketCamera, false)
		rocketCamera = nil
	end

	if targetingScaleform and HasScaleformMovieLoaded(targetingScaleform) then
		SetScaleformMovieAsNoLongerNeeded(targetingScaleform)
	end
	targetingScaleform = RocketTargetingCameraScaleform("instructional_buttons")

	rocketCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
	local camPos = vector3(anchorWorld.x, anchorWorld.y, anchorWorld.z + lift)
	camPos = RocketClampCamToPlayerRange(camPos, playerXY, ROCKET_MAX_RANGE_FROM_PLAYER)
	camPos = projectCamOntoStrikeLine(camPos)
	camPos = RocketClampCamToPlayerRange(camPos, playerXY, ROCKET_MAX_RANGE_FROM_PLAYER)
	camPos = projectCamOntoStrikeLine(camPos)
	SetCamCoord(rocketCamera, camPos.x, camPos.y, camPos.z)
	SetCamRot(rocketCamera, -90.0, 0.0, initYaw, 2)

	SetCamFov(rocketCamera, 75.0)
	RenderScriptCams(true, true, 900, true, true)
	FreezeEntityPosition(ped, true)

	-- MortarUiShow()

	local confirmPressed = false
	local cancelPressed = false

	CreateThread(function()
		local lastStrikeHudM = nil
		while true do
			Wait(0)
			local dt = GetFrameTime()
			if dt <= 0.0 or dt > 0.1 then
				dt = 0.016
			end
			local stepXY = ROCKET_MOVE_SPEED * dt
			local stepZ = ROCKET_VERT_SPEED * dt
			DisableAllControlActions(0)
			EnableControlAction(0, 202, true)
			EnableControlAction(0, 201, true)
			EnableControlAction(0, 172, true)
			EnableControlAction(0, 173, true)
			EnableControlAction(0, 44, true)
			EnableControlAction(0, 47, true)

			if IsControlPressed(0, 172) then
				camPos = camPos + vector3(axisX, axisY, 0.0) * stepXY
			end
			if IsControlPressed(0, 173) then
				camPos = camPos - vector3(axisX, axisY, 0.0) * stepXY
			end
			if IsControlPressed(0, 44) then
				camPos = camPos + vector3(0.0, 0.0, stepZ)
				if camPos.z > baseZ + maxZ then
					camPos = vector3(camPos.x, camPos.y, baseZ + maxZ)
				end
			end
			if IsControlPressed(0, 47) then
				camPos = camPos - vector3(0.0, 0.0, stepZ)
				if camPos.z < baseZ + minZ then
					camPos = vector3(camPos.x, camPos.y, baseZ + minZ)
				end
			end

			camPos = projectCamOntoStrikeLine(camPos)
			camPos = RocketClampCamToPlayerRange(camPos, playerXY, ROCKET_MAX_RANGE_FROM_PLAYER)
			camPos = projectCamOntoStrikeLine(camPos)

			SetCamCoord(rocketCamera, camPos.x, camPos.y, camPos.z)

			if targetingScaleform and HasScaleformMovieLoaded(targetingScaleform) then
				DrawScaleformMovieFullscreen(targetingScaleform, 255, 255, 255, 255, 0)
			end

			if IsControlJustPressed(0, 201) then
				confirmPressed = true
				break
			end
			if IsControlJustPressed(0, 202) then
				cancelPressed = true
				break
			end

			-- [[
			local foundGround, groundZ = GetGroundZFor_3dCoord(camPos.x, camPos.y, camPos.z + 200.0, false)
			local tgtZ = foundGround and groundZ or camPos.z
			local tgtDraw = vector3(camPos.x, camPos.y, tgtZ + 1.0)
			local aLift = vector3(anchorWorld.x, anchorWorld.y, anchorWorld.z + 0.35)

			DrawMarker(28, tgtDraw.x, tgtDraw.y, tgtDraw.z, 0, 0, 0, 0, 180.0, 0, 1.7, 1.7, 1.7, 255, 180, 0, 220, false, true, 2, false, nil, nil, false)

			if point2World then
				local ok2, gz2 = GetGroundZFor_3dCoord(point2World.x, point2World.y, point2World.z + 50.0, false)
				local p2z = ok2 and gz2 or point2World.z
				local p2Draw = vector3(point2World.x, point2World.y, p2z + 0.45)
				DrawMarker(28, p2Draw.x, p2Draw.y, p2Draw.z, 0, 0, 0, 0, 0, 0, 0.45, 0.45, 0.45, 255, 60, 60, 200, false, true, 2, false, nil, nil, false)
				DrawLine(aLift.x, aLift.y, aLift.z, p2Draw.x, p2Draw.y, p2Draw.z, 255, 80, 80, 200)
				DrawLine(p2Draw.x, p2Draw.y, p2Draw.z, tgtDraw.x, tgtDraw.y, tgtDraw.z, 255, 200, 40, 180)
			else
				DrawLine(aLift.x, aLift.y, aLift.z, tgtDraw.x, tgtDraw.y, tgtDraw.z, 255, 255, 0, 150)
			end
			-- ]]

			local m = math.floor(#(playerXY - vector3(camPos.x, camPos.y, 0.0)) + 0.5)
			if m ~= lastStrikeHudM then
				lastStrikeHudM = m
				pcall(function()
					MortarBridge.ShowHelpText(tostring(m), "top-center")
				end)
			end
		end

		-- MortarUiHide()

		pcall(function()
			MortarBridge.HideHelpText()
		end)

		if targetingScaleform and HasScaleformMovieLoaded(targetingScaleform) then
			SetScaleformMovieAsNoLongerNeeded(targetingScaleform)
			targetingScaleform = nil
		end

		RenderScriptCams(false, true, 550, true, true)
		DestroyCam(rocketCamera, false)
		rocketCamera = nil
		FreezeEntityPosition(ped, false)

		if cancelPressed then
			MortarBridge.Notify(MortarBridge.lang("info.target_cancelled"), "error")
			return
		end

		local foundGround, groundZ = GetGroundZFor_3dCoord(camPos.x, camPos.y, camPos.z + 200.0, false)
		local tgtZ = foundGround and groundZ or camPos.z
		local nid = activeTargetingNetId
		activeTargetingNetId = nil
		if nid then
			TriggerServerEvent("mortar:server:setTarget", nid, { x = camPos.x, y = camPos.y, z = tgtZ })
		end
	end)
end

local function RocketAddTargetOptions(ent, netId)
	if not ent or not DoesEntityExist(ent) or not netId then
		return
	end
	local nid = netId
	MortarBridge.TargetRemoveEntity(ent)
	MortarBridge.TargetAddEntity(ent, {
		options = {
			{
				type = "client",
				name = ("mortar_set_strike_%s"):format(nid),
				label = MortarBridge.lang("target.set_strike"),
				icon = "fas fa-ruler-combined",
				action = function()
					rocketObject = ent
					activeTargetingNetId = nid
					RocketStartTargetingCamera()
				end,
			},
			{
				type = "client",
				name = ("mortar_move_base_%s"):format(nid),
				label = MortarBridge.lang("target.move_base"),
				icon = "fas fa-arrows-alt",
				action = function()
					TriggerEvent("mortar:client:moveChair", nid)
				end,
			},
			{
				type = "client",
				name = ("mortar_fire_%s"):format(nid),
				label = MortarBridge.lang("target.fire"),
				icon = "fas fa-bomb",
				canInteract = function()
					local mm = mortars[nid]
					return mm and mm.targetCoords ~= nil
				end,
				action = function()
					TriggerServerEvent("mortar:server:requestLaunch", nid)
				end,
			},
			{
				type = "client",
				name = ("mortar_remove_base_%s"):format(nid),
				label = MortarBridge.lang("target.remove_base"),
				icon = "fas fa-box-open",
				action = function()
					TriggerServerEvent("mortar:server:removeBase", nid)
				end,
			},
		},
		distance = 2.5,
	})
end

local function CancelRocketPlacement()
	if rocketPlacementKeepEntity then
		local mid = movingMortarNetId
		rocketPlacing = false
		placementPreviewObject = nil
		if mid and mortars[mid] and mortars[mid].entity and DoesEntityExist(mortars[mid].entity) then
			local ent = mortars[mid].entity
			SetEntityAlpha(ent, 255, false)
			SetEntityCollision(ent, true, true)
			FreezeEntityPosition(ent, false)
			PlaceObjectOnGroundProperly(ent)
			FreezeEntityPosition(ent, true)
			RocketAddTargetOptions(ent, mid)
		end
		movingMortarNetId = nil
		rocketPlacementKeepEntity = false
		MortarBridge.Notify(MortarBridge.lang("info.move_cancelled"), "error")
		return
	end
	rocketPlacing = false
	if placementPreviewObject and DoesEntityExist(placementPreviewObject) then
		DeleteEntity(placementPreviewObject)
		placementPreviewObject = nil
	end
	MortarBridge.Notify(MortarBridge.lang("info.placement_cancelled"), "error")
end

local function RunRocketPlacementLoop(startHeading)
	local heading = startHeading
	local form = placementScaleform or RocketSetupScaleform("instructional_buttons")
	placementScaleform = form
	while rocketPlacing do
		local hit, coordsRay = RayCastGamePlayCamera(20.0)
		DrawScaleformMovieFullscreen(form, 255, 255, 255, 255, 0)
		local obj = placementPreviewObject or rocketObject
		if hit and obj and DoesEntityExist(obj) then
			SetEntityCoords(obj, coordsRay.x, coordsRay.y, coordsRay.z, false, false, false, false)
		end
		if IsControlJustPressed(0, 174) then
			heading = heading + 5.0
			if heading > 360.0 then
				heading = 0.0
			end
		end
		if IsControlJustPressed(0, 175) then
			heading = heading - 5.0
			if heading < 0.0 then
				heading = 360.0
			end
		end
		if IsControlJustPressed(0, 44) then
			CancelRocketPlacement()
		elseif obj and DoesEntityExist(obj) then
			SetEntityHeading(obj, heading)
		end
		if IsControlJustPressed(0, 38) then
			rocketPlacing = false
		end
		Wait(1)
	end
	if placementScaleform and HasScaleformMovieLoaded(placementScaleform) then
		SetScaleformMovieAsNoLongerNeeded(placementScaleform)
		placementScaleform = nil
	end
end

local function RocketFinalizePlacement()
	local isMove = rocketPlacementKeepEntity == true
	local moveNetId = isMove and movingMortarNetId or nil
	local obj = isMove and (placementPreviewObject or rocketObject) or placementPreviewObject
	if not obj or not DoesEntityExist(obj) then
		return
	end
	local coords = GetEntityCoords(obj)
	local h = GetEntityHeading(obj)
	rocketPlacementKeepEntity = false
	movingMortarNetId = nil

	if not isMove then
		if placementPreviewObject and DoesEntityExist(placementPreviewObject) then
			DeleteEntity(placementPreviewObject)
			placementPreviewObject = nil
		end
	else
		SetEntityAlpha(obj, 255, false)
		SetEntityCollision(obj, true, true)
		FreezeEntityPosition(obj, true)
		placementPreviewObject = nil
	end

	TriggerServerEvent("mortar:server:finalizeChair", { x = coords.x, y = coords.y, z = coords.z }, h, isMove, moveNetId)
	if isMove then
		MortarBridge.Notify(MortarBridge.lang("info.updating_position"), "primary", 4000)
		if moveNetId and obj and DoesEntityExist(obj) then
			if mortars[moveNetId] then
				mortars[moveNetId].entity = obj
			end
			RocketAddTargetOptions(obj, moveNetId)
		end
	end
end

RegisterNetEvent("mortar:client:chairSpawned", function(netId, _chairCoordsData)
	netId = tonumber(netId)
	if not netId then
		return
	end
	local ent = WaitForNetworkedEntity(netId, 12000)
	if ent == 0 then
		MortarBridge.Notify(MortarBridge.lang("error.cannot_sync_entity"), "error")
		return
	end
	mortars[netId] = mortars[netId] or {}
	mortars[netId].entity = ent
	SetEntityAlpha(ent, 255, false)
	SetEntityCollision(ent, true, true)
	FreezeEntityPosition(ent, true)
	RocketAddTargetOptions(ent, netId)
end)

RegisterNetEvent("mortar:client:fullStateSync", function(list)
	if type(list) ~= "table" then
		return
	end
	for i = 1, #list do
		local row = list[i]
		local netId = row and tonumber(row.netId)
		if netId then
			local ent = WaitForNetworkedEntity(netId, 12000)
			if ent ~= 0 then
				mortars[netId] = mortars[netId] or {}
				mortars[netId].entity = ent
				SetEntityAlpha(ent, 255, false)
				SetEntityCollision(ent, true, true)
				FreezeEntityPosition(ent, true)
				RocketAddTargetOptions(ent, netId)
				local tgt = row.target
				if tgt and tgt.x then
					mortars[netId].targetCoords = vector3(tgt.x, tgt.y, tgt.z)
					if mortars[netId].blip and DoesBlipExist(mortars[netId].blip) then
						RemoveBlip(mortars[netId].blip)
					end
					mortars[netId].blip = AddBlipForCoord(tgt.x, tgt.y, tgt.z)
					SetBlipSprite(mortars[netId].blip, 84)
					SetBlipColour(mortars[netId].blip, 1)
					SetBlipScale(mortars[netId].blip, 0.95)
					BeginTextCommandSetBlipName("STRING")
					AddTextComponentString(MortarBridge.lang("blip.strike_target"))
					EndTextCommandSetBlipName(mortars[netId].blip)
				end
			end
		end
	end
end)

RegisterNetEvent("mortar:client:syncTarget", function(netId, tgt)
	netId = tonumber(netId)
	if not netId or not tgt or not tgt.x then
		return
	end
	local m = mortars[netId]
	if not m or not m.entity then
		return
	end
	m.targetCoords = vector3(tgt.x, tgt.y, tgt.z)
	if m.blip and DoesBlipExist(m.blip) then
		RemoveBlip(m.blip)
	end
	m.blip = AddBlipForCoord(tgt.x, tgt.y, tgt.z)
	SetBlipSprite(m.blip, 84)
	SetBlipColour(m.blip, 1)
	SetBlipScale(m.blip, 0.95)
	BeginTextCommandSetBlipName("STRING")
	AddTextComponentString(MortarBridge.lang("blip.strike_target"))
	EndTextCommandSetBlipName(m.blip)
	MortarBridge.Notify(MortarBridge.lang("success.strike_synced"), "success", 6500)
end)

RegisterNetEvent("mortar:client:clearTarget", function(netId)
	mortarClearStrikeVisual(netId)
end)

RegisterNetEvent("mortar:client:chairRemoved", function(netId)
	netId = tonumber(netId)
	if not netId then
		return
	end
	mortarClearStrikeVisual(netId)
	local m = mortars[netId]
	if m and m.entity and DoesEntityExist(m.entity) then
		MortarBridge.TargetRemoveEntity(m.entity)
	end
	mortars[netId] = nil
end)

local function RocketApplyDamageInRadius(center, radius, damage)
	local c = vector3(center.x, center.y, center.z)
	local function hurtPed(ped)
		if not DoesEntityExist(ped) or IsEntityDead(ped) then
			return
		end
		local ec = GetEntityCoords(ped)
		local dx, dy, dz = ec.x - c.x, ec.y - c.y, ec.z - c.z
		if math.sqrt(dx * dx + dy * dy + dz * dz) <= radius then
			ApplyDamageToPed(ped, damage, false)
		end
	end
	local pool = GetGamePool and GetGamePool("CPed")
	if pool and #pool > 0 then
		for i = 1, #pool do
			hurtPed(pool[i])
		end
	else
		for _, pid in ipairs(GetActivePlayers()) do
			hurtPed(GetPlayerPed(pid))
		end
	end
end

RegisterNetEvent("mortar:client:syncLaunch", function(payload)
	if not payload or not payload.target or not payload.target.x then
		return
	end
	local t = payload.target
	local o = payload.origin or t
	local impact = vector3(t.x, t.y, t.z)
	local spawnZ = (o.z or 0.0) + (Config.RocketSpawnHeight or 120.0)
	local spawn = vector3(o.x, o.y, spawnZ)
	local dist = #(impact - spawn)
	local prepSec = clamp(
		(dist / 100.0) * (Config.RocketPrepPer100m or 0.85),
		Config.RocketPrepMinSeconds or 1.0,
		Config.RocketPrepMaxSeconds or 14.0
	)
	local flightSec = clamp(
		dist / math.max(1.0, Config.RocketFlightSpeedMps or 92.0),
		Config.RocketFlightMinSeconds or 0.75,
		Config.RocketFlightMaxSeconds or 32.0
	)
	local distM = math.floor(dist + 0.5)
	local totalEta = prepSec + flightSec
	MortarBridge.Notify(
		MortarBridge.lang("info.rocket_inbound"),
		"error",
		math.min(9000, math.floor(totalEta * 1000) + 1500)
	)
	CreateThread(function()
		Wait(math.floor(prepSec * 1000))
		local rocketHash = GetHashKey("w_lr_rpg_rocket")
		RequestModel(rocketHash)
		while not HasModelLoaded(rocketHash) do
			Wait(0)
		end
		local rocket = CreateObject(rocketHash, spawn.x, spawn.y, spawn.z, false, false, false)
		local startMs = GetGameTimer()
		local flightMs = math.max(1, math.floor(flightSec * 1000))
		local endMs = startMs + flightMs
		while GetGameTimer() < endMs do
			local u = (GetGameTimer() - startMs) / flightMs
			if u > 1.0 then
				u = 1.0
			end
			local p = spawn + (impact - spawn) * u
			SetEntityCoords(rocket, p.x, p.y, p.z, false, false, false, false)
			Wait(0)
		end
		SetEntityCoords(rocket, impact.x, impact.y, impact.z, false, false, false, false)
		AddExplosion(impact.x, impact.y, impact.z, 29, 10.0, true, false, 1.0)
		RocketApplyDamageInRadius(impact, ROCKET_DAMAGE_RADIUS, 200)
		if DoesEntityExist(rocket) then
			DeleteEntity(rocket)
		end
		if payload.mortarNetId then
			mortarClearStrikeVisual(payload.mortarNetId)
		end
		MortarBridge.Notify(MortarBridge.lang("success.strike_complete"), "success", 5000)
	end)
end)

RegisterNetEvent("mortar:client:useMortarItem", function()
	if rocketPlacing then
		return
	end
	rocketPlacing = true
	rocketPlacementKeepEntity = false
	rocketObject = nil
	local ped = PlayerPedId()
	local coords = GetEntityCoords(ped)
	local forward = GetEntityForwardVector(ped)
	local spawnCoords = coords + (forward * 2.0)
	local model = Config.ModelProp
	local hash = joaat(model)
	RequestModel(hash)
	while not HasModelLoaded(hash) do
		Wait(0)
	end
	placementPreviewObject = CreateObject(hash, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false)
	SetEntityHeading(placementPreviewObject, 0.0)
	SetEntityAlpha(placementPreviewObject, 150, false)
	SetEntityCollision(placementPreviewObject, false, false)
	FreezeEntityPosition(placementPreviewObject, true)
	CreateThread(function()
		RunRocketPlacementLoop(0.0)
		if not placementPreviewObject or not DoesEntityExist(placementPreviewObject) then
			return
		end
		RocketFinalizePlacement()
	end)
end)

RegisterNetEvent("mortar:client:moveChair", function(mortarNetId)
	mortarNetId = tonumber(mortarNetId)
	local m = mortarNetId and mortars[mortarNetId]
	local ent = m and m.entity
	if not ent or not DoesEntityExist(ent) or rocketPlacing then
		return
	end
	movingMortarNetId = mortarNetId
	rocketObject = ent
	TriggerServerEvent("mortar:server:moveChairStart", mortarNetId)
	MortarBridge.TargetRemoveEntity(ent)
	mortarClearStrikeVisual(mortarNetId)
	rocketPlacementKeepEntity = true
	rocketPlacing = true
	local h = GetEntityHeading(ent)
	SetEntityAlpha(ent, 150, false)
	SetEntityCollision(ent, false, false)
	FreezeEntityPosition(ent, true)
	placementPreviewObject = ent
	CreateThread(function()
		RunRocketPlacementLoop(h)
		if not placementPreviewObject or not DoesEntityExist(placementPreviewObject) then
			return
		end
		RocketFinalizePlacement()
	end)
end)

AddEventHandler("onResourceStop", function(resource)
	if resource ~= GetCurrentResourceName() then
		return
	end
	MortarUiHide()
	for nid in pairs(mortars) do
		mortarClearStrikeVisual(nid)
	end
	if placementPreviewObject and DoesEntityExist(placementPreviewObject) then
		if not rocketPlacementKeepEntity then
			DeleteEntity(placementPreviewObject)
		end
	end
	placementPreviewObject = nil
	if rocketCamera then
		RenderScriptCams(false, true, 350, true, true)
		DestroyCam(rocketCamera, false)
		rocketCamera = nil
	end
end)
