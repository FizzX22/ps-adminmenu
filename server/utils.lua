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

--- Sends a discord webhook log for admin actions.
--- @param module string
--- @param action string
--- @param source number
--- @param target number|string|nil
--- @param extra table|string|nil
function LogAdminAction(module, action, source, target, extra)
    if not Config.DiscordLogs or not Config.DiscordLogs.enabled then return end
    if not Config.DiscordLogs.webhook or Config.DiscordLogs.webhook == '' then return end
    if Config.DiscordLogs.modules and Config.DiscordLogs.modules[module] == false then return end

    local adminName = getPlayerNameBySource(source)
    local adminLicense = getIdentifierByType(source, 'license')
    local adminDiscord = getIdentifierByType(source, 'discord')

    local targetText = 'N/A'
    if target then
        local targetSource = tonumber(target)
        if targetSource then
            targetText = ('%s (%s)'):format(getPlayerNameBySource(targetSource), targetSource)
        else
            targetText = serializeValue(target)
        end
    end

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
                    { name = 'Admin', value = ('%s (%s)'):format(adminName, source), inline = false },
                    { name = 'Admin License', value = adminLicense, inline = false },
                    { name = 'Admin Discord', value = adminDiscord, inline = false },
                    { name = 'Target', value = trimForDiscord(targetText, 900), inline = false },
                    { name = 'Details', value = ('```json\n%s\n```'):format(extraText), inline = false },
                },
                footer = {
                    text = os.date('%Y-%m-%d %H:%M:%S')
                }
            }
        }
    }

    PerformHttpRequest(Config.DiscordLogs.webhook, function(err)
        if err and err ~= 204 and err ~= 200 then
            print(('[ps-adminmenu] failed to send webhook log (%s - %s): %s'):format(module, action, err))
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
