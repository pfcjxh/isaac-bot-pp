# FAQ

**The F8 menu shows boxes / garbage.**
The game's CJK pixel font in current builds reports widths but has no glyphs, so non-ASCII text
renders as boxes. The menu is ASCII on purpose. If you switch the game language, item names follow
the game's language.

**"Achievements are disabled" warning.**
That is the game's own message when mods are active. Kill Mom (Depths II) once with **all mods and
the console disabled** to clear it, or accept it. It is not produced by this mod.

**The bot does nothing.**
Check the bottom-left status: `PP | Off ...` means it is disabled. Press **F9** (or the Run switch
in F8). Also close the menu if it is open.

**`luamod isaac_bot` does nothing.**
Make sure the folder is `mods/isaac_bot/main.lua`, mods are enabled, and the console is enabled.
Check `log.txt` for `loaded v...` and `[IsaacBot] ERROR` lines.

**How do I reset the learned enemy data?**
Delete the mod save (the same place presets and stats live). All of it resets together.

**Does it work in online co-op?**
Use it single-player only. Mods in online rooms affect other players and the run.

**Why does it not use pills?**
Pill effects are hidden until tested and a bad one can end a run; the bot is conservative. Cards
have known effects and are used.
