MortarBridge = MortarBridge or {}

local function bridge()
	return exports["community_bridge"]:Bridge()
end

if IsDuplicityVersion() then
	function MortarBridge.lang(key, ...)
		return bridge().Language.Locale(key, ...)
	end

	function MortarBridge.NotifyPlayer(source, text, notifyType, durationMs)
		bridge().Notify.SendNotification(source, nil, text, notifyType or "primary", durationMs or 5000)
	end

	function MortarBridge.GetPlayer(source)
		return bridge().Framework.GetPlayer(source)
	end

	function MortarBridge.PlayerRemoveItem(player, itemName, amount)
		if not player or not player.PlayerData then
			return false
		end
		return bridge().Inventory.RemoveItem(player.PlayerData.source, itemName, amount or 1)
	end

	function MortarBridge.PlayerAddItem(player, itemName, amount)
		if not player or not player.PlayerData then
			return false
		end
		return bridge().Inventory.AddItem(player.PlayerData.source, itemName, amount or 1)
	end

	function MortarBridge.RegisterUsableItem(itemName, callback)
		bridge().Framework.RegisterUsableItem(itemName, callback)
	end

	function MortarBridge.OnServerPlayerLoaded(callback)
		AddEventHandler("community_bridge:Server:OnPlayerLoaded", function(src)
			local Player = bridge().Framework.GetPlayer(src)
			if Player then
				callback(Player)
			end
		end)
	end
else
	function MortarBridge.lang(key, ...)
		return bridge().Language.Locale(key, ...)
	end
	function MortarBridge.Notify(text, notifyType, durationMs)
		bridge().Notify.SendNotification(nil, text, notifyType or "primary", durationMs or 5000)
	end

	function MortarBridge.TargetRemoveEntity(entity)
		if not entity or entity == 0 then
			return
		end
		pcall(function()
			bridge().Target.RemoveLocalEntity(entity, nil)
		end)
	end

	function MortarBridge.TargetAddEntity(entity, opts)
		if not entity or entity == 0 or not opts then
			return
		end
		local inner = opts.options or opts
		local dist = opts.distance
		if dist and type(inner) == "table" then
			for _, opt in ipairs(inner) do
				opt.distance = opt.distance or dist
			end
		end
		bridge().Target.AddLocalEntity(entity, inner)
	end

	function MortarBridge.ShowHelpText(message, position)
		bridge().HelpText.ShowHelpText(message, position)
	end

	function MortarBridge.HideHelpText()
		bridge().HelpText.HideHelpText()
	end
end
