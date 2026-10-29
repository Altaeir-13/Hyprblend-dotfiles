local home_dir = os.getenv("HOME")

-- User binaries (~/.local/bin)
local xdg_bin_home = os.getenv("XDG_BIN_HOME") or (home_dir .. "/.local/bin")
local path_old = os.getenv("PATH") or "/usr/local/sbin:/usr/local/bin:/usr/bin"
if not string.find(":" .. path_old .. ":", ":" .. xdg_bin_home .. ":", 1, true) then
    hl.env("PATH", xdg_bin_home .. ":" .. path_old)
end

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
hl.env("XDG_DATA_DIRS", home_dir .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share:" .. xdg_data_dirs_old)

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")
