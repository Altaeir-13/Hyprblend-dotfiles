-- This file sources other files in `hyprland` and `custom` folders
-- You wanna add your stuff in files in `custom`

-- Internal stuff --
require("hyprland.lib")
require("hyprland.services")

-- Environment variables --
require("hyprland.env")
if is_file_exists(HOME .. "/.config/hypr/custom/env.lua") then
    require("custom.env")
end

-- Default configurations --
require("hyprland.execs")
require("hyprland.general")
require("hyprland.rules")
require("hyprland.colors")
require("hyprland.keybinds")

-- Custom configurations --
if is_file_exists(HOME .. "/.config/hypr/custom/execs.lua") then
    require("custom.execs")
end
if is_file_exists(HOME .. "/.config/hypr/custom/general.lua") then
    require("custom.general")
end
if is_file_exists(HOME .. "/.config/hypr/custom/rules.lua") then
    require("custom.rules")
end
if is_file_exists(HOME .. "/.config/hypr/custom/keybinds.lua") then
    require("custom.keybinds")
end

-- nwg-displays support --
if is_file_exists(HOME .. "/.config/hypr/workspaces.lua") then
    require("workspaces")
end
if is_file_exists(HOME .. "/.config/hypr/monitors.lua") then
    require("monitors")
end

-- Shell overrides --
require("hyprland.shellOverrides.main")

-- BEGIN CAELESTIA HYBRID BINDS
--
-- IMPORTANT:
-- This is intentionally AFTER hyprland.shellOverrides.main.
-- Therefore these bindings win over end-4's shell bindings.

local function hybrid_frontend()
    local home_dir = os.getenv("HOME") or ""
    local state_base = os.getenv("XDG_STATE_HOME") or (home_dir .. "/.local/state")
    local state_path = state_base .. "/quickshell/ui-switch/current"

    local value = "end4"

    local f = io.open(state_path, "r")

    if f then
        value = f:read("*l") or "end4"
        f:close()
    end

    -- Não confiar apenas no arquivo de estado.
    --
    -- Ele pode sobreviver a reboot/logout e dizer
    -- "caelestia" quando o frontend ativo é end-4.
    if value ~= "caelestia" then
        return "end4"
    end

    -- Caelestia só recebe seus binds se sua instância
    -- Quickshell realmente já estiver rodando.
    local proc =
        io.popen("qs list --all 2>/dev/null")

    if not proc then
        return "end4"
    end

    local instances =
        proc:read("*a") or ""

    proc:close()

    local caelestia_running =
        string.find(
            instances,
            "/quickshell/caelestia-hybrid/shell.qml",
            1,
            true
        ) ~= nil

    if caelestia_running then
        return "caelestia"
    end

    return "end4"
end


if hybrid_frontend() == "caelestia" then

    -- ========================================================
    -- REMOVE END-4 SUPER BINDS
    --
    -- end-4 registers more than one bind for these keys:
    -- overview, fallback launcher and workspace-number handling.
    -- ========================================================

    for _ = 1, 16 do
        pcall(function()
            hl.unbind("SUPER + SUPER_L")
        end)

        pcall(function()
            hl.unbind("SUPER + SUPER_R")
        end)

        pcall(function()
            hl.unbind("SUPER_L")
        end)

        pcall(function()
            hl.unbind("SUPER_R")
        end)
    end


    -- ========================================================
    -- SUPER -> CAELESTIA LAUNCHER
    --
    -- Direct IPC.
    -- No GlobalShortcut indirection.
    -- No fuzzel fallback.
    -- ========================================================

    hl.bind(
        "SUPER + SUPER_L",
        hl.dsp.exec_cmd(
            "qs -c caelestia-hybrid "
            .. "ipc call drawers toggle launcher"
        ),
        {
            release = true,
            description = "HYBRID: Caelestia launcher"
        }
    )

    hl.bind(
        "SUPER + SUPER_R",
        hl.dsp.exec_cmd(
            "qs -c caelestia-hybrid "
            .. "ipc call drawers toggle launcher"
        ),
        {
            release = true,
            description = "HYBRID: Caelestia launcher"
        }
    )


    -- ========================================================
    -- REMOVE END-4 BRIGHTNESS BINDS
    -- ========================================================

    for _ = 1, 8 do
        pcall(function()
            hl.unbind("XF86MonBrightnessUp")
        end)

        pcall(function()
            hl.unbind("XF86MonBrightnessDown")
        end)

        pcall(function()
            hl.unbind("F5")
        end)

        pcall(function()
            hl.unbind("F6")
        end)
    end


    -- ========================================================
    -- BRIGHTNESS -> CAELESTIA BRIGHTNESS SERVICE
    --
    -- This is the important difference:
    --
    -- keyboard
    --    ↓
    -- Caelestia Brightness.qml
    --    ↓
    -- monitor.brightness changes
    --    ↓
    -- Caelestia OSD detects the change
    --    ↓
    -- brightness slider appears
    --
    -- Brightness.qml accepts +5% and 5%- natively.
    -- ========================================================

    hl.bind(
        "XF86MonBrightnessUp",
        hl.dsp.exec_cmd(
            "qs -c caelestia-hybrid "
            .. "ipc call brightness set '+5%'"
        ),
        {
            repeating = true,
            locked = true,
            description = "HYBRID: Caelestia brightness up"
        }
    )

    hl.bind(
        "XF86MonBrightnessDown",
        hl.dsp.exec_cmd(
            "qs -c caelestia-hybrid "
            .. "ipc call brightness set '5%-'"
        ),
        {
            repeating = true,
            locked = true,
            description = "HYBRID: Caelestia brightness down"
        }
    )

    -- Also cover laptops whose firmware exposes literal F5/F6.
    hl.bind(
        "F5",
        hl.dsp.exec_cmd(
            "qs -c caelestia-hybrid "
            .. "ipc call brightness set '5%-'"
        ),
        {
            repeating = true,
            locked = true,
            description = "HYBRID: Caelestia brightness down F5"
        }
    )

    hl.bind(
        "F6",
        hl.dsp.exec_cmd(
            "qs -c caelestia-hybrid "
            .. "ipc call brightness set '+5%'"
        ),
        {
            repeating = true,
            locked = true,
            description = "HYBRID: Caelestia brightness up F6"
        }
    )
end

-- END CAELESTIA HYBRID BINDS

-- BEGIN HYBRID KEYBOARD SWITCH
--
-- Loaded after shellOverrides on purpose.
--
-- XKB's grp:win_space_toggle does the actual layout change.
-- This bind consumes the chord so Super release does not also
-- activate the launcher.
for _ = 1, 6 do
    pcall(function()
        hl.unbind("SUPER + Space")
    end)
end

hl.bind(
    "SUPER + Space",
    hl.dsp.no_op(),
    {
        description = "Switch keyboard layout: US / BR"
    }
)
-- END HYBRID KEYBOARD SWITCH

-- BEGIN HYBRID UNIVERSAL LOCK
--
-- Same Super+L entry point in both UI frontends.
for _ = 1, 12 do
    pcall(function()
        hl.unbind("SUPER + L")
    end)
end

local rice_lock_bin =
    (os.getenv("XDG_BIN_HOME") or ((os.getenv("HOME") or "") .. "/.local/bin"))
    .. "/rice-lock"

hl.bind(
    "SUPER + L",
    hl.dsp.exec_cmd(rice_lock_bin),
    {
        description = "Lock screen"
    }
)
-- END HYBRID UNIVERSAL LOCK
