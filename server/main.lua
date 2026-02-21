local coreResource = Config.Core == "qbx_core" and "qb-core" or Config.Core
QBCore = exports[coreResource]:GetCoreObject()

local function resolveActionConfig(key)
    if Config.Actions and Config.Actions[key] then
        return Config.Actions[key], 'Actions'
    end

    if Config.PlayerActions and Config.PlayerActions[key] then
        return Config.PlayerActions[key], 'Players'
    end

    if Config.OtherActions and Config.OtherActions[key] then
        return Config.OtherActions[key], 'OtherActions'
    end

    return nil, nil
end

lib.addCommand('admin', {
    help = 'Open the admin menu',
    restricted = 'qbcore.mod'
}, function(source)
    if not QBCore.Functions.IsOptin(source) then TriggerClientEvent('QBCore:Notify', source, 'You are not on admin duty', 'error'); return end
    TriggerClientEvent('ps-adminmenu:client:OpenUI', source)
end)

RegisterNetEvent('ps-adminmenu:server:ValidateClientAction', function(key, selectedData, event, perms)
    local src = source
    if not CheckPerms(src, perms) then return end
    TriggerClientEvent(event, src, key, selectedData)

    local actionConfig = resolveActionConfig(key)
    LogAdminAction('Main', 'ValidateClientAction', src, src, {
        key = key,
        label = actionConfig and actionConfig.label or key,
        event = event,
        selectedData = selectedData,
        perms = perms
    })
end)

RegisterNetEvent('ps-adminmenu:server:ValidateCommand', function(command, perms)
    local src = source
    if not CheckPerms(src, perms) then return end

    if command == 'vector2' or command == 'vector3' or command == 'vector4' or command == 'heading' then
        TriggerClientEvent('ps-adminmenu:client:CopyCoords', src, command)
        LogAdminAction('Main', 'ValidateCommand', src, src, { command = command, perms = perms })
    elseif command == 'setammo' then
        TriggerClientEvent('ps-adminmenu:client:SetAmmoCommand', src)
        LogAdminAction('Main', 'ValidateCommand', src, src, { command = command, perms = perms })
    end
end)

RegisterNetEvent('ps-adminmenu:server:LogMenuAction', function(key, selectedData)
    local src = source
    local actionConfig, actionGroup = resolveActionConfig(key)
    local actionData = CheckDataFromKey(key)

    if not actionConfig and not actionData then return end

    local requiredPerms = actionData and actionData.perms or actionConfig and actionConfig.perms
    if requiredPerms and not QBCore.Functions.HasPermission(src, requiredPerms) then return end

    local actionType = actionData and actionData.type or actionConfig and actionConfig.type
    local actionEvent = actionData and actionData.event or actionConfig and actionConfig.event

    LogAdminAction('Actions', 'MenuAction', src, src, {
        key = key,
        label = actionConfig and actionConfig.label or key,
        group = actionGroup or 'Unknown',
        type = actionType,
        event = actionEvent,
        perms = requiredPerms,
        selectedData = selectedData
    })
end)
