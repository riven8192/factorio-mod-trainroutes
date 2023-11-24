require 'rivenmods-common-v0-1-0'



routePrefix = 'Route: '
assignedToRoutePrefix = 'Assigned to route: '
routeNoPathPrefix = 'Route: no path'





function create_schedule_checksum(schedule)
	local serialized = deeptostring(schedule)
	local checksum = 0
	
	for idx = 1, #serialized do
		checksum = checksum * 17 + serialized:byte(idx)
		checksum = bit32.band(checksum, 16777215)
	end
	
	-- return checksum
	return serialized
end



function assign_train_to_route(defTrain, reqTrain, routeId)	
	-- copy (last) color
	local defLocomotiveColor = nil;
	for direction, defLocomotives in pairs(defTrain.locomotives) do
		for idx, defLocomotive in ipairs(defLocomotives) do
			defLocomotiveColor = defLocomotive.color
		end
	end
	
	if defLocomotiveColor then
		for direction, reqLocomotives in pairs(reqTrain.locomotives) do
			for idx, reqLocomotive in ipairs(reqLocomotives) do
				reqLocomotive.color = defLocomotiveColor
			end
		end
	end
	
	-- TODO capture station-name
	
	local a = deepcopy(defTrain.schedule)
	local b = deepcopy(reqTrain.schedule)
	a.records[1].station = ''
	b.records[1].station = ''
	a.current = -1
	b.current = -1
	a = deeptostring(a)
	b = deeptostring(b)
	if a == b then
		return false
	end
	
	-- copy schedule, change first station-name
	
	local newSchedule = deepcopy(defTrain.schedule)
	newSchedule.records[1].station = assignedToRoutePrefix .. routeId
	
	local currentTargetStation = reqTrain.schedule.records[reqTrain.schedule.current].station;
	for idx, record in pairs(newSchedule.records) do
		if record.station == currentTargetStation then
			newSchedule.current = idx
		end
	end	
	
	reqTrain.schedule = newSchedule
	reqTrain.manual_mode = false
	return true
end


function ensure_mod_context() 
	if not global.hasContext then
		global.hasContext = true;
		
		global.trainId2train = {}
		global.trainId2defRouteId = {}
		global.trainId2reqRouteId = {}
		global.trainId2curRouteId = {}
		global.defRouteId2trainId = {}
		global.defRouteId2checksum = {}
		global.defRouteId2changed = {}
		global.defRouteId2lastChangedAt = {}
	end
end


function build_route_mapping_based_on_trains()
	global.trainId2train = {}
	global.trainId2defRouteId = {}
	global.trainId2reqRouteId = {}
	global.trainId2curRouteId = {}
	global.defRouteId2trainId = {}
	global.defRouteId2changed = {}
	
	local defRouteId2checksumOld = shallowcopy(global.defRouteId2checksum);
	global.defRouteId2checksum = {}

	-- iterate all trains in all surfaces
	for _idx1_, surface in pairs(game.surfaces) do
		for _idx2_, train in pairs(surface.get_trains()) do
			local trainId = train.id
			global.trainId2train[trainId] = train
			
			if not (train.schedule and train.schedule.records) then
				goto continue
			end
			
			local scheduleRecordCount = table_length(train.schedule.records);
			if scheduleRecordCount == 0 then
				goto continue
			end
			
			local firstScheduleRecord = train.schedule.records[1]
			if firstScheduleRecord.station == nil then
				goto continue
			end
			
			if starts_with(firstScheduleRecord.station, routePrefix) then
				local routeId = firstScheduleRecord.station:sub(#routePrefix + 1)
				if scheduleRecordCount == 1 then
					-- trains with Route REQUESTS
					global.trainId2reqRouteId[trainId] = routeId
				else
					-- trains with Route DEFINITIONS
					global.trainId2defRouteId[trainId] = routeId
					global.defRouteId2trainId[routeId] = trainId
					
					-- did anything change in the schedule?
					local oldChecksum = defRouteId2checksumOld[routeId];
					local newChecksum = create_schedule_checksum(train.schedule);
					global.defRouteId2checksum[routeId] = newChecksum
						
					if not (oldChecksum == newChecksum) then
						global.defRouteId2changed[routeId] = true
					end
				end
			elseif starts_with(firstScheduleRecord.station, assignedToRoutePrefix) then
				local routeId = firstScheduleRecord.station:sub(#assignedToRoutePrefix + 1)
				if scheduleRecordCount > 1 then
					-- trains with Route ASSIGNED
					global.trainId2curRouteId[trainId] = routeId
				end
			end
			
			::continue::
		end
	end
end



function search_deftrain_based_on_routeid(routeId)
	
	if not global.defRouteId2trainId[routeId] then
		-- game.print('Failed to find Route ' .. routeId)
		return nil
	end
	local defTrainId = global.defRouteId2trainId[routeId]
	
	if not global.trainId2train[defTrainId] then
		game.print('Failed to find route \'' .. routeId .. '\' in train #' .. defTrainId)
		return nil
	end
	local defTrain = global.trainId2train[defTrainId]
	
	if not defTrain.schedule then
		game.print('Found empty train-schedule in route \'' .. routeId .. '\' in train #' .. defTrainId)
		return nil
	end
	
	return defTrain
end








script.on_event({defines.events.on_tick},
	function (e)
		if not (e.tick % 120 == 0) then
			return
		end
		
		ensure_mod_context();
		
		build_route_mapping_based_on_trains(e.tick);
		
		
			
		for reqTrainId, reqRouteId in pairs(global.trainId2reqRouteId) do
			local reqTrain = global.trainId2train[reqTrainId];
			local defTrain = search_deftrain_based_on_routeid(reqRouteId)
			
			if defTrain then
				if assign_train_to_route(defTrain, reqTrain, reqRouteId) then
					game.print('Assigned train #' .. reqTrain.id .. ' to route: ' .. reqRouteId);
				end
			end
		end
		
		
		
		-- only process route-definition changes, if the last change happened N ticks ago
		local minTimeElapsed = 3*60
		for chgRouteId, _val_ in pairs(global.defRouteId2changed) do
			global.defRouteId2lastChangedAt[chgRouteId] = e.tick
			global.defRouteId2changed[chgRouteId] = false
		end
		
		for chgRouteId, lastChangedAt in pairs(global.defRouteId2lastChangedAt) do
			if lastChangedAt and ((e.tick - lastChangedAt) > minTimeElapsed) then
				global.defRouteId2changed[chgRouteId] = true
				global.defRouteId2lastChangedAt[chgRouteId] = nil
			end
		end
		
		
		for chgRouteId, changed in pairs(global.defRouteId2changed) do
			if changed then
				local changedTrainCount = 0;
				for curTrainId, curRouteId in pairs(global.trainId2curRouteId) do
					if chgRouteId == curRouteId then				
						local curTrain = global.trainId2train[curTrainId];
						local defTrain = search_deftrain_based_on_routeid(chgRouteId)
						
						if defTrain then
							assign_train_to_route(defTrain, curTrain, chgRouteId)
							changedTrainCount = changedTrainCount + 1
						end
					end
				end			
				
				game.print('Updated schedules for ' .. changedTrainCount .. ' trains on route: ' .. chgRouteId)
			end
		end
	end
)
