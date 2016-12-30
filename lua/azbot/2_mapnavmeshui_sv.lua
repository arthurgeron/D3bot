
return function(lib)
	local from = lib.From

	local function getCursoredPosOrNil(pl)
		local trR = pl:GetEyeTrace()
		if not trR.Hit then return end
		return trR.HitPos
	end
	local function getCursoredNodeOrNil(pl)
		local item = lib.MapNavMesh:GetCursoredItemOrNil(pl)
		if not item or item.Type ~= "node" then return end
		return item
	end
	
	local selectedNodeOrNilByPl = {}
	local function hasSelection(pl) return not not selectedNodeOrNilByPl[pl] end
	local function clearSelection(pl)
		selectedNodeOrNilByPl[pl] = nil
		pl:SendLua(lib.GlobalK .. ".ClearMapNavMeshViewHighlights()")
	end
	local function trySelectCursoredNode(pl)
		clearSelection(pl)
		local cursoredNodeOrNil = getCursoredNodeOrNil(pl)
		selectedNodeOrNilByPl[pl] = cursoredNodeOrNil
		if not cursoredNodeOrNil then return end
		pl:SendLua(lib.GlobalK .. ".HighlightInMapNavMeshView(" .. cursoredNodeOrNil.Id .. ")")
	end
	
	local function round(num) return math.Round(num * 10) / 10 end
	
	local function setPos(node, pos)
		node:SetParam("X", round(pos.x))
		node:SetParam("Y", round(pos.y))
		node:SetParam("Z", round(pos.z))
	end
	
	local function getCursoredDirection(ang) return math.Round(math.abs(math.abs(ang) - 90) / 90) end
	local function getCursoredAxisName(pl, excludeZOrNil)
		local angs = pl:EyeAngles()
		if not excludeZOrNil and getCursoredDirection(angs.p) == 0 then return "Z" end
		return getCursoredDirection(angs.y) == 1 and "X" or "Y"
	end
	
	local editModes = {
		{	Name = "Create Node",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local cursoredPos = getCursoredPosOrNil(pl)
					if not cursoredPos then return end
					local node = lib.MapNavMesh:NewNode()
					setPos(node, cursoredPos)
					lib.UpdateMapNavMeshUiSubscribers()
				end } },
		{	Name = "Link Nodes",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local selectedNode = selectedNodeOrNilByPl[pl]
					if not selectedNode then
						trySelectCursoredNode(pl)
					else
						local node = getCursoredNodeOrNil(pl)
						if not node then return end
						lib.MapNavMesh:ForceGetLink(selectedNode, node)
						clearSelection(pl)
						lib.UpdateMapNavMeshUiSubscribers()
					end
				end } },
		{	Name = "Reposition Node",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local selectedNode = selectedNodeOrNilByPl[pl]
					if not selectedNode then
						trySelectCursoredNode(pl)
					else
						local cursoredPos = getCursoredPosOrNil(pl)
						if not cursoredPos then return end
						setPos(selectedNode, cursoredPos)
						lib.UpdateMapNavMeshUiSubscribers()
					end
				end,
				[IN_ATTACK2] = function(pl)
					local selectedNode = selectedNodeOrNilByPl[pl]
					if not selectedNode then return end
					local cursoredPos = getCursoredPosOrNil(pl)
					if not cursoredPos then return end
					local cursoredAxisName = getCursoredAxisName(pl)
					selectedNode:SetParam(cursoredAxisName, round(cursoredPos[cursoredAxisName:lower()]))
					lib.UpdateMapNavMeshUiSubscribers()
				end } },
		{	Name = "Resize Node Area",
			FuncByKey = {
				[IN_ATTACK] = trySelectCursoredNode,
				[IN_ATTACK2] = function(pl)
					local selectedNode = selectedNodeOrNilByPl[pl]
					if not selectedNode then return end
					local cursoredPos = getCursoredPosOrNil(pl)
					if not cursoredPos then return end
					local cursoredAxisName = getCursoredAxisName(pl, true)
					local cursoredPosKey = cursoredAxisName:lower()
					local cursoredDimension = round(cursoredPos[cursoredPosKey])
					selectedNode:SetParam("Area" .. cursoredAxisName .. (cursoredDimension < selectedNode.Pos[cursoredPosKey] and "Min" or "Max"), cursoredDimension)
					lib.UpdateMapNavMeshUiSubscribers()
				end } },
		{	Name = "Delete Item or Area",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local item = lib.MapNavMesh:GetCursoredItemOrNil(pl)
					if not item then return end
					item:Remove()
					lib.UpdateMapNavMeshUiSubscribers()
				end,
				[IN_ATTACK2] = function(pl)
					local item = lib.MapNavMesh:GetCursoredItemOrNil(pl)
					if not item then return end
					for idx, name in ipairs{ "AreaXMin", "AreaXMax", "AreaYMin", "AreaYMax" } do item:SetParam(name, "") end
					lib.UpdateMapNavMeshUiSubscribers()
				end } } }
	for idx, editMode in ipairs(editModes) do editMode.Next = editModes[(idx % #editModes) + 1] end
	
	local editModeByPl = {}
	
	local function printEditMode(pl) pl:ChatPrint("Edit Mode: " .. editModeByPl[pl].Name) end
	
	local subscribers = {}
	local subscriptionTypeOrNilByPl = {}
	
	function lib.BeMapNavMeshUiSubscriber(pl) if not subscriptionTypeOrNilByPl[pl] then lib.SetMapNavMeshUiSubscription(pl, "view") end end
	function lib.SetMapNavMeshUiSubscription(pl, subscriptionTypeOrNil)
		local formerSubscriptionTypeOrNil = subscriptionTypeOrNilByPl[pl]
		if subscriptionTypeOrNil == formerSubscriptionTypeOrNil then return end
		subscriptionTypeOrNilByPl[pl] = subscriptionTypeOrNil
		if formerSubscriptionTypeOrNil == nil then
			table.insert(subscribers, pl)
			lib.UploadMapNavMesh(pl)
			pl:SendLua(lib.GlobalK .. ".SetIsMapNavMeshViewEnabled(true)")
		elseif subscriptionTypeOrNil == nil then
			table.RemoveByValue(subscribers, pl)
			pl:SendLua(lib.GlobalK .. ".SetIsMapNavMeshViewEnabled(false)")
		end
		if formerSubscriptionTypeOrNil == "edit" then clearSelection(pl) end
		if subscriptionTypeOrNil == "edit" then
			editModeByPl[pl] = editModes[1]
			printEditMode(pl)
		end
	end

	function lib.UpdateMapNavMeshUiSubscribers() lib.UploadMapNavMesh(subscribers) end
	
	local pathDebugTimerIdPrefix = tostring({}) .. "-"
	local function getPathDebugTimerId(pl) return pathDebugTimerIdPrefix .. pl:EntIndex() end
	function lib.ShowMapNavMeshPath(pl, pathOrEntA, nilOrEntB)
		if nilOrEntB == nil then
			local path = pathOrEntA
			pl:SendLua(lib.GlobalK .. ".SetShownMapNavMeshPath{" .. (","):Implode(from(path):SelV(function(node) return node.Id end).R) .. "}")
			lib.BeMapNavMeshUiSubscriber(pl)
			return
		end
		local entA = pathOrEntA
		local entB = nilOrEntB
		local timerId = getPathDebugTimerId(pl)
		timer.Remove(timerId)
		timer.Create(timerId, 0.1, 0, function()
			local navMesh = lib.MapNavMesh
			local nodeA = navMesh:GetNearestNodeOrNil(entA:GetPos())
			local nodeB = navMesh:GetNearestNodeOrNil(entB:GetPos())
			lib.ShowMapNavMeshPath(pl, nodeA and nodeB and lib.GetBestMeshPathOrNil(nodeA, nodeB, lib.DeathCostOrNilByLink) or {})
		end)
	end
	function lib.HideMapNavMeshPath(pl)
		timer.Remove(getPathDebugTimerId(pl))
		pl:SendLua(lib.GlobalK .. ".SetShownMapNavMeshPath{}")
	end
	
	hook.Add("KeyPress", tostring({}), function(pl, key)
		if subscriptionTypeOrNilByPl[pl] ~= "edit" then return end
		if key == IN_RELOAD then
			if hasSelection(pl) then
				clearSelection(pl)
			else
				editModeByPl[pl] = editModeByPl[pl].Next
				printEditMode(pl)
			end
		else
			local func = editModeByPl[pl].FuncByKey[key]
			if func then func(pl) end
		end
	end)
end