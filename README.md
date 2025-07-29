# Navet's Projectile Aimbot

### This script is a work in progress!

The only setting that you gotta configure in the Lmaobox menu is the aim key!

If LMAOBOX's projectile aimbot is enabled, this script will disabled it when shooting with a projectile weapon (we dont need 2 aimbots running at the same time, do we?)

# Thank You

- [Terminator](https://github.com/titaniummachine1/) - for the localplayer's head position
- [GoodEvening](https://github.com/GoodEveningFellOff) - for the GetProjectileInformation function

### How to build

Requirements:

- [Luabundler](https://github.com/Benjamin-Dobell/luabundler) (If you're on NixOS, you can [use this](https://github.com/uosq/luabundler-nix))

Instructions:

```bash
git clone https://github.com/uosq/lbox-projectile-aimbot.git
cd lbox-projectile-aimbot
./merge.sh
```