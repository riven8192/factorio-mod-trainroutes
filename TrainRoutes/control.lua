function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end



function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function starts_with(str, start)
   return str:sub(1, #start) == start
end

function ends_with(str, ending)
   return ending == "" or str:sub(-#ending) == ending
end

function table_length(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end



function deeptostring(orig)
    local text
	if orig == nil then
		text = 'nil'
	elseif type(orig) == 'string' then
		text = '"' .. orig .. '"'
	elseif type(orig) == 'table' then
		text = ''
        for orig_key, orig_value in next, orig, nil do
            text = text .. deeptostring(orig_key) .. '=' .. deeptostring(orig_value) .. ','
        end
        -- text = '[' .. text .. deeptostring(getmetatable(orig)) .. ']'
        text = '[' .. text .. ']'
    else
        text = tostring(orig)
    end
    return text
end


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
	
	local currentTargetStation = reqTrain.schedule.records[reqTrain.schedule.current];
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
	if not global.modtrainroutes then
		global.modtrainroutes = {}
		global.modtrainroutes.trainId2train = {}
		global.modtrainroutes.trainId2defRouteId = {}
		global.modtrainroutes.trainId2reqRouteId = {}
		global.modtrainroutes.trainId2curRouteId = {}
		global.modtrainroutes.defRouteId2trainId = {}
		global.modtrainroutes.defRouteId2checksum = {}
		global.modtrainroutes.defRouteId2changed = {}
		global.modtrainroutes.defRouteId2lastChangedAt = {}
		global.modtrainroutes.station2id = {}
		global.modtrainroutes.id2station = {}
	end
end


function build_route_mapping_based_on_trains()
	global.modtrainroutes.trainId2train = {}
	global.modtrainroutes.trainId2defRouteId = {}
	global.modtrainroutes.trainId2reqRouteId = {}
	global.modtrainroutes.trainId2curRouteId = {}
	global.modtrainroutes.defRouteId2trainId = {}
	global.modtrainroutes.defRouteId2changed = {}
	
	local defRouteId2checksumOld = shallowcopy(global.modtrainroutes.defRouteId2checksum);
	global.modtrainroutes.defRouteId2checksum = {}

	-- iterate all trains in all surfaces
	for _idx1_, surface in pairs(game.surfaces) do
		for _idx2_, train in pairs(surface.get_trains()) do
			local trainId = train.id
			global.modtrainroutes.trainId2train[trainId] = train
			
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
					global.modtrainroutes.trainId2reqRouteId[trainId] = routeId
				else
					-- trains with Route DEFINITIONS
					global.modtrainroutes.trainId2defRouteId[trainId] = routeId
					global.modtrainroutes.defRouteId2trainId[routeId] = trainId
					
					-- did anything change in the schedule?
					local oldChecksum = defRouteId2checksumOld[routeId];
					local newChecksum = create_schedule_checksum(train.schedule);
					global.modtrainroutes.defRouteId2checksum[routeId] = newChecksum
						
					if not (oldChecksum == newChecksum) then
						global.modtrainroutes.defRouteId2changed[routeId] = true
					end
				end
			elseif starts_with(firstScheduleRecord.station, assignedToRoutePrefix) then
				local routeId = firstScheduleRecord.station:sub(#assignedToRoutePrefix + 1)
				if scheduleRecordCount > 1 then
					-- trains with Route ASSIGNED
					global.modtrainroutes.trainId2curRouteId[trainId] = routeId
				end
			end
			
			::continue::
		end
	end
end



function search_deftrain_based_on_routeid(routeId)
	
	if not global.modtrainroutes.defRouteId2trainId[routeId] then
		-- game.print('Failed to find Route ' .. routeId)
		return nil
	end
	local defTrainId = global.modtrainroutes.defRouteId2trainId[routeId]
	
	if not global.modtrainroutes.trainId2train[defTrainId] then
		game.print('Failed to find route \'' .. routeId .. '\' in train #' .. defTrainId)
		return nil
	end
	local defTrain = global.modtrainroutes.trainId2train[defTrainId]
	
	if not defTrain.schedule then
		game.print('Found empty train-schedule in route \'' .. routeId .. '\' in train #' .. defTrainId)
		return nil
	end
	
	return defTrain
end




function add_train_contents_to_station(train, stationId, stationId2item2count)
	local item2count = stationId2item2count[stationId]
	if not item2count then
		item2count = {}
		stationId2item2count[stationId] = item2count
	end
	
	for itemName, itemCount in pairs(train.get_contents()) do
		local curCount = item2count[itemName]
		if not curCount then
			curCount = 0
		end
		item2count[itemName] = curCount + itemCount
	end
end




function stationToId(station)
	for idx, elem in pairs(global.modtrainroutes.station2id) do
		if elem == station then
			return idx
		end
	end
	
	table.insert(global.modtrainroutes.station2id, station)
	local stationId = table_length(global.modtrainroutes.station2id) -- table.getn(global.modtrainroutes.station2id)
	global.modtrainroutes.id2station[stationId] = station
	return stationId
end


-- script.on_event({defines.input_action.drag_train_schedule},
-- 	function (e)
-- 		game.print('DRAGGED TRAIN SCHEDULE');
-- 	end
-- )

script.on_event({defines.input_action.edit_train_schedule},
	function (e)
		game.print('EDITED TRAIN SCHEDULE');
	end
)




script.on_event({defines.events.on_tick},
	function (e)
		if not (e.tick % 120 == 0) then
			return
		end
		
		ensure_mod_context();
		
		build_route_mapping_based_on_trains(e.tick);
		
		local stationName2stationList = {}
		local stationId2arrivalTrainIds = {}
		local stationId2item2count = {}
		
		for trainId, curRouteId in pairs(global.modtrainroutes.trainId2curRouteId) do
			local reqTrain = global.modtrainroutes.trainId2train[trainId];
			if reqTrain.state == defines.train_state.no_path then
				-- game.print('No path found for train #' .. reqTrain.id .. ' on route: ' .. curRouteId);
				
				
			end
			
			if reqTrain.station or reqTrain.path_end_stop then
				local station = nil
				if reqTrain.station then
					station = reqTrain.station
				else 
					station = reqTrain.path_end_stop
				end
				local stationId = stationToId(station)
				local stationName = station.backer_name

				
				
				local arrivalTrainIds = stationId2arrivalTrainIds[stationId]
				if not arrivalTrainIds then
					arrivalTrainIds = {}
					stationId2arrivalTrainIds[stationId] = arrivalTrainIds
				end
				arrivalTrainIds[trainId] = true

				
				
				local stationList = stationName2stationList[stationName]
				if not stationList then
					stationList = {}
					stationName2stationList[stationName] = stationList
				end
				table.insert(stationList, station)
				
				
				add_train_contents_to_station(reqTrain, stationId, stationId2item2count)				
			end
		end
		
		for stationId, station in pairs(global.modtrainroutes.id2station) do
			if station.valid then
				for _idx2_, conn in pairs(station.circuit_connection_definitions) do
					if conn.wire == defines.wire_type.red and conn.target_entity and conn.target_entity.type == 'constant-combinator' then
						local slot = conn.target_entity.get_control_behavior()
					
						slot.set_signal(1, nil);
						slot.set_signal(2, nil);
						slot.set_signal(3, nil);
						
						-- game.print('Resetting station #' .. station.backer_name);
					end
				end
			end
		end
		
		for stationId, item2count in pairs(stationId2item2count) do
			local station = global.modtrainroutes.id2station[stationId]
			
			for _idx2_, conn in pairs(station.circuit_connection_definitions) do
				if conn.wire == defines.wire_type.red and conn.target_entity and conn.target_entity.type == 'constant-combinator' then
					local slot = conn.target_entity.get_control_behavior()
					
					slot.set_signal(1, nil);
					slot.set_signal(2, nil);
					slot.set_signal(3, nil);
					
					
					local _idx3_ = 1
					for item, count in pairs(item2count) do
						slot.set_signal(_idx3_, {signal={type='item'; name=item}; count=count});
						_idx3_ = _idx3_ + 1
					end
				end
			end
		end
		
		
		
		
			
		for reqTrainId, reqRouteId in pairs(global.modtrainroutes.trainId2reqRouteId) do
			local reqTrain = global.modtrainroutes.trainId2train[reqTrainId];
			local defTrain = search_deftrain_based_on_routeid(reqRouteId)
			
			if defTrain then
				if assign_train_to_route(defTrain, reqTrain, reqRouteId) then
					game.print('Assigned train #' .. reqTrain.id .. ' to route: ' .. reqRouteId);
				end
			end
		end
		
		
		
		-- only process route-definition changes, if the last change happened N ticks ago
		local minTimeElapsed = 3*60
		for chgRouteId, _val_ in pairs(global.modtrainroutes.defRouteId2changed) do
			global.modtrainroutes.defRouteId2lastChangedAt[chgRouteId] = e.tick
			global.modtrainroutes.defRouteId2changed[chgRouteId] = false
			-- game.print('Found updated schedules for route: ' .. chgRouteId .. ' (but not applying them yet)')
		end
		
		for chgRouteId, lastChangedAt in pairs(global.modtrainroutes.defRouteId2lastChangedAt) do
			if lastChangedAt and ((e.tick - lastChangedAt) > minTimeElapsed) then
				global.modtrainroutes.defRouteId2changed[chgRouteId] = true
				global.modtrainroutes.defRouteId2lastChangedAt[chgRouteId] = nil
			end
		end
		
		
		for chgRouteId, changed in pairs(global.modtrainroutes.defRouteId2changed) do
			if changed then
				local changedTrainCount = 0;
				for curTrainId, curRouteId in pairs(global.modtrainroutes.trainId2curRouteId) do
					if chgRouteId == curRouteId then				
						local curTrain = global.modtrainroutes.trainId2train[curTrainId];
						local defTrain = search_deftrain_based_on_routeid(chgRouteId)
						
						if defTrain then
							-- game.print('Updated schedule of train #' .. curTrain.id .. ' on route \'' .. chgRouteId .. '\'');
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
