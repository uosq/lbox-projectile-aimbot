# Navet's Projectile Aimbot

### This script is a work in progress!

Most settings of the aimbot are configured on lbox menu (ignore cloaked, bonked, aim fov, aim key, etc)

If LMAOBOX's projectile aimbot is enabled, this script will be disabled when using a projectile weapon :) (we dont need 2 aimbots running at the same time, do we?)

### Features
- Options on the lbox menu that affect the script:
   - aim key
   - aim fov
   - auto shoot
   - ignore cloaked
   - ignore bonked
   - ignore taunting
   - ignore disguised

### How to build

Requirements:

- [Luabundler](https://github.com/Benjamin-Dobell/luabundler) (If you're on NixOS, you can [use this](https://github.com/uosq/luabundler-nix))

Instructions:

```bash
git clone https://github.com/uosq/lbox-projectile-aimbot.git
cd lbox-projectile-aimbot
./merge.sh
```