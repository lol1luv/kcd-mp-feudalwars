#!/bin/bash
# Feudal Wars starter: syncs the mode from GitHub, then launches the server.
# No GitHub API calls (they rate-limit a shared IP and silently skip updates):
# the whole repo head comes from codeload and a manifest hash decides.
set -u
cd "$(dirname "$0")" || exit 1

REPO="lol1luv/kcd-mp-feudalwars"
START_VERSION="2026-11-24.2"

say()  { echo "[fw] $*"; }
warn() { echo "[fw] WARNING: $*"; }
fail() { echo "[fw] ERROR: $*"; }

say "=============================================================="
say "Feudal Wars starter $START_VERSION"
say "repo $REPO (main), $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
say "=============================================================="

mkdir -p tmp
export TMPDIR="$PWD/tmp" TMP="$PWD/tmp" TEMP="$PWD/tmp"

# ---------------------------------------------------------------- server.toml

# Level override FIRST (before the sync): Wings sometimes fails to rewrite
# server.toml from the Startup variable, so enforce it here.
LEVEL_WANT="${LEVEL:-kutnohorsko}"
say "level: env LEVEL='${LEVEL:-<unset>}' -> want '$LEVEL_WANT'"
if [ -f server.toml ]; then
  if grep -qE '^[[:space:]]*level[[:space:]]*=' server.toml; then
    sed -i -E "s|^[[:space:]]*level[[:space:]]*=.*|level = \"$LEVEL_WANT\"|" server.toml
  else
    printf '\n[server]\nlevel = "%s"\n' "$LEVEL_WANT" >> server.toml
  fi
  say "level: server.toml now $(grep -E '^[[:space:]]*level[[:space:]]*=' server.toml | head -1 | tr -d '\r')"
else
  warn "no server.toml, the server will use its own defaults"
fi

# The map must be on, or CreateMapObject is refused ("no map") and nothing the mode
# builds appears. Add [world] map if the file lacks it (older installs).
if [ -f server.toml ] && ! grep -qE '^[[:space:]]*map[[:space:]]*=' server.toml; then
  if grep -qE '^\[world\]' server.toml; then
    sed -i -E '0,/^\[world\]/s//[world]\nmap = "data\/maps\/{level}"/' server.toml
  else
    printf '\n[world]\nmap = "data/maps/{level}"\n' >> server.toml
  fi
  say "map: [world] map enabled in server.toml"
fi

# ---------------------------------------------------------------- sync

sha_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# A manifest hash of the whole mode folder: every file's path and content, so a
# change in any module or UI file is seen, not only the entry script.
manifest_of() {
  local dir="$1"
  [ -d "$dir" ] || { echo "none"; return; }
  ( cd "$dir" && find . -type f | sort | while read -r f; do
      printf '%s  %s\n' "$(sha_of "$f")" "$f"
    done ) | sha256sum | cut -d' ' -f1
}

count_files() { [ -d "$1" ] && find "$1" -type f | wc -l | tr -d ' ' || echo 0; }

if [ "${AUTO_UPDATE:-1}" != "1" ]; then
  say "auto-update OFF (AUTO_UPDATE=${AUTO_UPDATE:-1}), starting the local build as it stands"
else
  say "sync: downloading $REPO main ..."
  UPDTMP="$PWD/tmp/sync"
  rm -rf "$UPDTMP"; mkdir -p "$UPDTMP"
  DL_OK=0
  for attempt in 1 2 3; do
    if curl -sSLf --max-time 180 "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" -o "$UPDTMP/src.tar.gz" \
      && tar xzf "$UPDTMP/src.tar.gz" -C "$UPDTMP"; then
      DL_OK=1
      break
    fi
    warn "sync: download attempt $attempt failed, retrying in 3s"
    rm -rf "$UPDTMP"; mkdir -p "$UPDTMP"
    sleep 3
  done
  if [ "$DL_OK" = "1" ]; then
    SRC_DIR="$(find "$UPDTMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
    say "sync: downloaded $(wc -c < "$UPDTMP/src.tar.gz" | tr -d ' ') bytes, unpacked to $(basename "$SRC_DIR")"

    # --- the entry script (gamemodes/feudalwars.lua) ---
    REMOTE_LUA="$SRC_DIR/gamemodes/feudalwars.lua"
    LOCAL_LUA="./gamemodes/feudalwars.lua"
    if [ ! -f "$REMOTE_LUA" ]; then
      fail "the repo has no gamemodes/feudalwars.lua - keeping the local build"
    else
      REMOTE_HASH="$(sha_of "$REMOTE_LUA")"
      LOCAL_HASH="$(sha_of "$LOCAL_LUA")"
      if [ "$REMOTE_HASH" = "$LOCAL_HASH" ]; then
        say "entry: gamemodes/feudalwars.lua is current (${REMOTE_HASH:0:12})"
      else
        mkdir -p gamemodes
        cp -f "$REMOTE_LUA" "$LOCAL_LUA"
        say "entry: gamemodes/feudalwars.lua updated (${LOCAL_HASH:0:12} -> ${REMOTE_HASH:0:12})"
      fi
    fi

    # --- the mode folder (modules + UI): exact mirror every boot ---
    REMOTE_MODE="$SRC_DIR/gamemodes/feudalwars"
    LOCAL_MODE="./gamemodes/feudalwars"
    if [ ! -d "$REMOTE_MODE" ]; then
      fail "the repo has no gamemodes/feudalwars/ folder - keeping the local build"
    else
      REMOTE_MAN="$(manifest_of "$REMOTE_MODE")"
      LOCAL_MAN="$(manifest_of "$LOCAL_MODE")"
      REMOTE_N="$(count_files "$REMOTE_MODE")"
      LOCAL_N="$(count_files "$LOCAL_MODE")"
      if [ "$REMOTE_MAN" = "$LOCAL_MAN" ]; then
        say "mode: gamemodes/feudalwars/ is current ($REMOTE_N files, ${REMOTE_MAN:0:12})"
      else
        say "mode: gamemodes/feudalwars/ changed ($LOCAL_N -> $REMOTE_N files), mirroring it"
        rm -rf "$LOCAL_MODE"
        mkdir -p "$LOCAL_MODE"
        cp -rf "$REMOTE_MODE"/. "$LOCAL_MODE"/
        say "mode: mirrored $(count_files "$LOCAL_MODE") files, ${REMOTE_MAN:0:12}"
      fi

      # what is inside, so the log shows the modules and the UI at a glance
      MODULES="$(cd "$LOCAL_MODE" 2>/dev/null && ls -1 *.lua 2>/dev/null | tr '\n' ' ')"
      UI_N="$(count_files "$LOCAL_MODE/ui")"
      say "mode: modules: ${MODULES:-<none>}"
      say "mode: ui: $UI_N files"
    fi

    # --- the starter refreshes itself too (takes effect next boot) ---
    if [ -f "$SRC_DIR/pterodactyl-start.sh" ]; then
      if ! cmp -s "$SRC_DIR/pterodactyl-start.sh" ./start.sh; then
        cp -f "$SRC_DIR/pterodactyl-start.sh" ./start.sh.new && mv -f ./start.sh.new ./start.sh && chmod +x ./start.sh
        say "starter: start.sh updated (runs from the next restart)"
      else
        say "starter: start.sh is current"
      fi
    fi

    say "sync: done"
  else
    warn "sync download failed after 3 attempts - starting the local build as it stands"
  fi
  rm -rf "$UPDTMP"
fi

# ---------------------------------------------------------------- launch

export DOTNET_ROOT="$PWD/dotnet" DOTNET_ROOT_X64="$PWD/dotnet"

if [ -f gamemodes/feudalwars.lua ]; then
  say "launch: gamemodes/feudalwars.lua ($(wc -c < gamemodes/feudalwars.lua | tr -d ' ') bytes, $(wc -l < gamemodes/feudalwars.lua | tr -d ' ') lines)"
else
  fail "gamemodes/feudalwars.lua is missing - the server will start with no mode"
fi
say "launch: ./KcdMp.Server --config server.toml --gamemode gamemodes/feudalwars.lua"
say "=============================================================="

exec ./KcdMp.Server --config server.toml --gamemode gamemodes/feudalwars.lua
