local function noPerms(source)
    QBCore.Functions.Notify(source, "You are not Admin or God.", 'error')
end

--- @param perms string
function CheckPerms(source, perms)
    local hasPerms = QBCore.Functions.HasPermission(source, perms)
    if not hasPerms then
        return noPerms(source)
    end

    return hasPerms
end

local function getIdentifierByType(source, identifierType)
    if not source then return "n/a" end
    local identifier = QBCore.Functions.GetIdentifier(source, identifierType)
    return identifier or "n/a"
end

local function getPlayerNameBySource(playerSource)
    local name = GetPlayerName(playerSource)
    return name or ('Unknown (%s)'):format(playerSource or 'n/a')
end

local function serializeValue(value)
    local valueType = type(value)

    if valueType == 'table' then
        local success, encoded = pcall(json.encode, value)
        if success then return encoded end
        return '[table]'
    end

    if value == nil then
        return 'nil'
    end

    return tostring(value)
end

local function trimForDiscord(value, maxLength)
    if #value <= maxLength then return value end
    return value:sub(1, maxLength - 3) .. '...'
end

local function parseSelectedData(selectedData)
    if type(selectedData) ~= 'table' then return {} end

    local parsed = {}
    for field, data in pairs(selectedData) do
        if type(data) == 'table' then
            parsed[field] = {
                label = data.label,
                value = data.value
            }
        else
            parsed[field] = data
        end
    end

    return parsed
end

local function resolveModuleSettings(module)
    local logs = Config.DiscordLogs or {}
    local modules = logs.modules or {}
    local moduleSettings = modules[module]

    if moduleSettings == false then
        return false, nil
    end

    if type(moduleSettings) == 'table' and moduleSettings.enabled == false then
        return false, nil
    end

    local webhooks = logs.webhooks or {}
    local configuredWebhook = type(moduleSettings) == 'table' and moduleSettings.webhook or nil

    if configuredWebhook and configuredWebhook:find('https://') == 1 then
        return true, configuredWebhook
    end

    if configuredWebhook and webhooks[configuredWebhook] and webhooks[configuredWebhook] ~= '' then
        return true, webhooks[configuredWebhook]
    end

    if webhooks.default and webhooks.default ~= '' then
        return true, webhooks.default
    end

    if logs.webhook and logs.webhook ~= '' then
        return true, logs.webhook
    end

    return false, nil
end

local function getPlayerContext(source)
    local player = QBCore.Functions.GetPlayer(source)
    local context = {
        name = getPlayerNameBySource(source),
        license = getIdentifierByType(source, 'license'),
        discord = getIdentifierByType(source, 'discord'),
        fivem = getIdentifierByType(source, 'fivem'),
        ip = getIdentifierByType(source, 'ip'),
    }

    if player then
        context.citizenid = player.PlayerData.citizenid or 'n/a'
        context.job = player.PlayerData.job and player.PlayerData.job.name or 'n/a'
        context.gang = player.PlayerData.gang and player.PlayerData.gang.name or 'n/a'
    else
        context.citizenid = 'n/a'
        context.job = 'n/a'
        context.gang = 'n/a'
    end

    return context
end

local function formatTarget(target)
    if not target then return 'N/A' end

    local targetSource = tonumber(target)
    if targetSource then
        local info = getPlayerContext(targetSource)
        return trimForDiscord((
            '%s (%s)\nCID: %s\nDiscord: %s\nLicense: %s'
        ):format(info.name, targetSource, info.citizenid, info.discord, info.license), 1000)
    end

    return trimForDiscord(serializeValue(target), 1000)
end

--- Sends a discord webhook log for admin actions.
--- @param module string
--- @param action string
--- @param source number
--- @param target number|string|nil
--- @param extra table|string|nil
function LogAdminAction(module, action, source, target, extra)
    if not Config.DiscordLogs or not Config.DiscordLogs.enabled then return end

    local canLog, webhookUrl = resolveModuleSettings(module)
    if not canLog or not webhookUrl then return end

    local admin = getPlayerContext(source)
    local extraText = extra and serializeValue(extra) or 'N/A'
    extraText = trimForDiscord(extraText, 900)

    local payload = {
        username = Config.DiscordLogs.username,
        avatar_url = Config.DiscordLogs.avatarUrl,
        embeds = {
            {
                title = ('ps-adminmenu | %s'):format(module),
                color = Config.DiscordLogs.color,
                fields = {
                    { name = 'Action', value = action, inline = true },
                    { name = 'Module', value = module, inline = true },
                    { name = 'Admin', value = trimForDiscord(('%s (%s)'):format(admin.name, source), 1000), inline = false },
                    { name = 'Admin IDs', value = trimForDiscord((
                        'CID: %s\nDiscord: %s\nLicense: %s\nFiveM: %s\nIP: %s\nJob: %s\nGang: %s'
                    ):format(admin.citizenid, admin.discord, admin.license, admin.fivem, admin.ip, admin.job, admin.gang), 1000), inline = false },
                    { name = 'Target', value = formatTarget(target), inline = false },
                    { name = 'Details', value = ('```json\n%s\n```'):format(extraText), inline = false },
                },
                footer = {
                    text = os.date('%Y-%m-%d %H:%M:%S')
                }
            }
        }
    }

    PerformHttpRequest(webhookUrl, function(statusCode, responseBody)
        if statusCode ~= 204 and statusCode ~= 200 then
            print(('[ps-adminmenu] failed webhook log (%s - %s). status=%s body=%s'):format(
                module,
                action,
                tostring(statusCode),
                trimForDiscord(tostring(responseBody or 'n/a'), 600)
            ))
        end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

function LogAdminActionFromSelection(module, action, source, selectedData, targetKey)
    local target = targetKey and selectedData and selectedData[targetKey] and selectedData[targetKey].value or nil
    LogAdminAction(module, action, source, target, parseSelectedData(selectedData))
end

function CheckDataFromKey(key)
    local actions = Config.Actions[key]
    if actions then
        local data = nil

        if actions.event then
            data = actions
        end

        if actions.dropdown then
            for _, v in pairs(actions.dropdown) do
                if v.event then
                    local new = v
                    new.perms = actions.perms
                    data = new
                    break
                end
            end
        end

        return data
    end

    local playerActions = Config.PlayerActions[key]
    if playerActions then
        return playerActions
    end

    local otherActions = Config.OtherActions[key]
    if otherActions then
        return otherActions
    end
end

---@param plate string
---@return boolean
function CheckAlreadyPlate(plate)
    local vPlate = QBCore.Shared.Trim(plate)
    local result = MySQL.single.await("SELECT plate FROM player_vehicles WHERE plate = ?", { vPlate })
    if result and result.plate then return true end
    return false
end

lib.callback.register('ps-adminmenu:callback:CheckPerms', function(source, perms)
    return CheckPerms(source, perms)
end)

lib.callback.register('ps-adminmenu:callback:CheckAlreadyPlate', function(_, vPlate)
    return CheckAlreadyPlate(vPlate)
end)

--- @param source number
--- @param target number
function CheckRoutingbucket(source, target)
    local sourceBucket = GetPlayerRoutingBucket(source)
    local targetBucket = GetPlayerRoutingBucket(target)

    if sourceBucket == targetBucket then return end

    SetPlayerRoutingBucket(source, targetBucket)
    QBCore.Functions.Notify(source, locale("bucket_set", targetBucket), 'error', 7500)
end
