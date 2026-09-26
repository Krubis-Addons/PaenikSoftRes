-- luacheck-Konfiguration für WoW-Addons (Lua 5.1)
std = "lua51"
max_line_length = false
exclude_files = { "**/Libs/**" }

ignore = {
    "212/self", -- unbenutztes self-Argument
    "113",      -- Lesen undefinierter Globals: WoW hat tausende; Tippfehler findet der Lua-Sprachserver
}

-- Globals, die das Addon SETZEN darf (alles andere wird als Leak gemeldet):
globals = {
    "PaenikSoftResDB",
    "PaenikSoftResDebugLog",
    "SlashCmdList",
    "SLASH_PAENIKSOFTRES1",
}
