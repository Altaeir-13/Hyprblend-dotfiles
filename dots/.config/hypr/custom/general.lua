-- BEGIN HYBRID KEYBOARD LAYOUT
--
-- English (US) + Portuguese (Brazil).
--
-- XKB itself handles Super+Space. A no-op Hyprland bind is
-- installed after shellOverrides in hyprland.lua so releasing
-- Super does not also open the launcher.
hl.config({
    input = {
        kb_layout = "us,br",
        kb_options = "grp:win_space_toggle",
    },
})
-- END HYBRID KEYBOARD LAYOUT
