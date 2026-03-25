local Mortars = {}

local function mortarDeleteEntity(netId)
	local m = Mortars[netId]
	if not m then
		return
	end
	if m.entity and DoesEntityExist(m.entity) then
		DeleteEntity(m.entity)
	end
	Mortars[netId] = nil
end

local function deleteAllMortars()
	for netId in pairs(Mortars) do
		mortarDeleteEntity(netId)
	end
end

local function broadcastClearTarget(netId)
	local m = Mortars[netId]
	if m then
		m.target = nil
	end
	TriggerClientEvent("mortar:client:clearTarget", -1, netId)
end

RegisterNetEvent("mortar:server:finalizeChair", function(coords, heading, isMove, mortarNetId)
	local src = source
	if coords == nil then
		return
	end
	local cx = coords.x or coords[1]
	local cy = coords.y or coords[2]
	local cz = coords.z or coords[3]
	if not cx or not cy or not cz then
		return
	end

	local ped = GetPlayerPed(src)
	if not ped or ped == 0 then
		return
	end
	local px, py, pz = table.unpack(GetEntityCoords(ped))
	local dx, dy = cx - px, cy - py
	if (dx * dx + dy * dy) ^ 0.5 > Config.MaxPlaceDistanceFromPlayer + 5.0 then
		return
	end

	isMove = isMove == true
	mortarNetId = tonumber(mortarNetId)

	if isMove then
		if not mortarNetId or not Mortars[mortarNetId] then
			return
		end
		local m = Mortars[mortarNetId]
		if not m.entity or not DoesEntityExist(m.entity) then
			return
		end
		SetEntityCoords(m.entity, cx, cy, cz, false, false, false, false)
		SetEntityHeading(m.entity, heading or 0.0)
		FreezeEntityPosition(m.entity, true)
		m.coords = { x = cx, y = cy, z = cz }
		return
	end

	local Player = MortarBridge.GetPlayer(src)
	if not Player then
		return
	end
	if not MortarBridge.PlayerRemoveItem(Player, Config.ItemName, 1) then
		MortarBridge.NotifyPlayer(src, MortarBridge.lang("error.no_item"), "error")
		return
	end

	local model = joaat(Config.ModelProp)

	CreateThread(function()
		local ent = CreateObject(model, cx, cy, cz, true, true, false)
		local timeout = GetGameTimer() + 8000
		while not DoesEntityExist(ent) and GetGameTimer() < timeout do
			Wait(10)
		end
		if not DoesEntityExist(ent) then
			local P = MortarBridge.GetPlayer(src)
			if P then
				MortarBridge.PlayerAddItem(P, Config.ItemName, 1)
			end
			MortarBridge.NotifyPlayer(src, MortarBridge.lang("error.spawn_failed"), "error")
			return
		end
		SetEntityHeading(ent, heading or 0.0)
		FreezeEntityPosition(ent, true)
		local netId = NetworkGetNetworkIdFromEntity(ent)
		Mortars[netId] = {
			entity = ent,
			coords = { x = cx, y = cy, z = cz },
			target = nil,
		}
		TriggerClientEvent("mortar:client:chairSpawned", -1, netId, Mortars[netId].coords)
	end)
end)

RegisterNetEvent("mortar:server:setTarget", function(mortarNetId, coords)
	local src = source
	mortarNetId = tonumber(mortarNetId)
	local m = mortarNetId and Mortars[mortarNetId]
	if not m or not m.coords or not coords then
		return
	end
	local tx = coords.x or coords[1]
	local ty = coords.y or coords[2]
	local tz = coords.z or coords[3]
	if not tx or not ty or not tz then
		return
	end
	local dx = tx - m.coords.x
	local dy = ty - m.coords.y
	if (dx * dx + dy * dy) ^ 0.5 > Config.MaxRangeFromPlayer + 10.0 then
		return
	end
	m.target = { x = tx, y = ty, z = tz }
	TriggerClientEvent("mortar:client:syncTarget", -1, mortarNetId, m.target)
end)

RegisterNetEvent("mortar:server:clearTarget", function(mortarNetId)
	mortarNetId = tonumber(mortarNetId)
	if mortarNetId and Mortars[mortarNetId] then
		broadcastClearTarget(mortarNetId)
	end
end)

RegisterNetEvent("mortar:server:requestLaunch", function(mortarNetId)
	mortarNetId = tonumber(mortarNetId)
	local m = mortarNetId and Mortars[mortarNetId]
	if not m or not m.target or not m.coords then
		return
	end
	TriggerClientEvent("mortar:client:syncLaunch", -1, {
		target = m.target,
		origin = m.coords,
		mortarNetId = mortarNetId,
	})
	broadcastClearTarget(mortarNetId)
end)

RegisterNetEvent("mortar:server:moveChairStart", function(mortarNetId)
	mortarNetId = tonumber(mortarNetId)
	if mortarNetId and Mortars[mortarNetId] then
		broadcastClearTarget(mortarNetId)
	end
end)

RegisterNetEvent("mortar:server:removeBase", function(mortarNetId)
	local src = source
	mortarNetId = tonumber(mortarNetId)
	local m = mortarNetId and Mortars[mortarNetId]
	if not m or not m.entity or not DoesEntityExist(m.entity) then
		MortarBridge.NotifyPlayer(src, MortarBridge.lang("error.cannot_remove"), "error")
		return
	end

	local Player = MortarBridge.GetPlayer(src)
	if not Player then
		return
	end
	if not MortarBridge.PlayerAddItem(Player, Config.ItemName, 1) then
		MortarBridge.NotifyPlayer(src, MortarBridge.lang("error.no_inventory_space"), "error")
		return
	end

	broadcastClearTarget(mortarNetId)
	DeleteEntity(m.entity)
	Mortars[mortarNetId] = nil

	TriggerClientEvent("mortar:client:chairRemoved", -1, mortarNetId)
	MortarBridge.NotifyPlayer(src, MortarBridge.lang("success.removed_returned"), "success")
end)

AddEventHandler("onResourceStop", function(res)
	if res ~= GetCurrentResourceName() then
		return
	end
	deleteAllMortars()
end)

MortarBridge.RegisterUsableItem(Config.ItemName, function(source, _item)
	TriggerClientEvent("mortar:client:useMortarItem", source)
end)

MortarBridge.OnServerPlayerLoaded(function(Player)
	local src = Player.PlayerData.source
	local list = {}
	for netId, m in pairs(Mortars) do
		if m.coords then
			list[#list + 1] = {
				netId = netId,
				coords = m.coords,
				target = m.target,
			}
		end
	end
	if #list > 0 then
		TriggerClientEvent("mortar:client:fullStateSync", src, list)
	end
end)
