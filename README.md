# factorio-checker

Scripts for checking sanity of Factorio prototypes.

# How to Use

1. Add `data-final-fixes.lua`.
1. Launch Factorio and wait until the main menu.
1. Run `$ extract-data.sh <path to factorio-current.log>` to create `data-raw.lua` in the CWD.
1. Run Lua scripts in the same directory as `data-raw.lua`.
