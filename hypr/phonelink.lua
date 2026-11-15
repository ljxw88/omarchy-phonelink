-- phonelink: use your Android phone from Omarchy (built on scrcpy).
-- https://github.com/ljxw88/omarchy-phonelink
--
-- Updates replace this file unless you've edited it, in which case the new
-- version is saved beside it as phonelink.lua.new.

-- The bindings and rules below use Omarchy's helpers.
if not o then
  return
end

-- Super + Alt + V switches the focused phone window's sound between this
-- computer and the phone.
-- To keep these keys for something else, set `phonelink_bindings = false` in
-- hyprland.lua above the line that loads this file.
if phonelink_bindings ~= false then
  o.bind("SUPER + ALT + P", "Phone apps", "phonelink apps")
  o.bind("SUPER + ALT + SHIFT + P", "Mirror phone screen", "phonelink mirror")
  o.bind("SUPER + ALT + V", "Phone window sound: computer or phone", "phonelink sound toggle")
end

-- The mirror's class is "phonelink"; each phone app is "phonelink.<package>".
-- Both tile like any other window. Phone apps resize with their tile; the
-- mirror keeps the phone's shape inside its tile.
o.window("^phonelink(\\..+)?$", { tag = "+phone" })

-- Watching something fullscreen shouldn't let the screen go to sleep.
o.window({ tag = "phone" }, { idle_inhibit = "fullscreen" })

-- Floated with Super + T, the mirror keeps the phone's proportions.
o.window("^phonelink$", { keep_aspect_ratio = true })

-- To float the mirror by default instead, uncomment:
-- o.window("^phonelink$", { float = true, center = true })
