#!/bin/bash
# Feudal Wars starter: syncs the mode from GitHub, then launches the server.
# No GitHub API calls (they rate-limit a shared IP and silently skip updates):
# the main tarball comes from codeload and a sha256 of the mode file decides.
set -u
cd "$(dirname "$0")" || exit 1

REPO="lol1luv/kcd-mp-feudalwars"

mkdir -p tmp
export TMPDIR="$PWD/tmp" TMP="$PWD/tmp" TEMP="$PWD/tmp"

# Level override FIRST (before the sync): Wings sometimes fails to rewrite
# server.toml from the Startup variable, so enforce it here.
LEVEL_WANT="${LEVEL:-kutnohorsko}"
echo "LEVEL env = '${LEVEL:-<unset>}' -> want '$LEVEL_WANT'"
if [ -f server.toml ]; then
  if grep -qE '^[[:space:]]*level[[:space:]]*=' server.toml; then
    sed -i -E "s|^[[:space:]]*level[[:space:]]*=.*|level = \"$LEVEL_WANT\"|" server.toml
  else
    printf '\n[server]\nlevel = "%s"\n' "$LEVEL_WANT" >> server.toml
  fi
  echo "server.toml level now: $(grep -E '^[[:space:]]*level[[:space:]]*=' server.toml || echo '<none>')"
else
  echo "WARNING: no server.toml, the server will use its own defaults."
fi

# The map must be on, or CreateMapObject is refused ("no map") and nothing the mode
# builds appears. Add [world] map if the file lacks it (older installs).
if [ -f server.toml ] && ! grep -qE '^[[:space:]]*map[[:space:]]*=' server.toml; then
  if grep -qE '^\[world\]' server.toml; then
    sed -i -E '0,/^\[world\]/s//[world]\nmap = "data\/maps\/{level}"/' server.toml
  else
    printf '\n[world]\nmap = "data/maps/{level}"\n' >> server.toml
  fi
  echo "server.toml: [world] map enabled"
fi

sha_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

if [ "${AUTO_UPDATE:-1}" != "1" ]; then
  echo "Auto-update off (AUTO_UPDATE=${AUTO_UPDATE:-1}), starting the local build."
else
  echo "Syncing Feudal Wars from $REPO (main)..."
  UPDTMP="$PWD/tmp/sync"
  rm -rf "$UPDTMP"; mkdir -p "$UPDTMP"
  if curl -sSLf --max-time 180 "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" -o "$UPDTMP/src.tar.gz" \
    && tar xzf "$UPDTMP/src.tar.gz" -C "$UPDTMP"; then
    SRC_DIR="$(find "$UPDTMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
    REMOTE_LUA="$SRC_DIR/gamemodes/feudalwars.lua"
    LOCAL_LUA="./gamemodes/feudalwars.lua"

    REMOTE_HASH="$(sha_of "$REMOTE_LUA")"
    LOCAL_HASH="$(sha_of "$LOCAL_LUA")"
    echo "mode hash remote=$REMOTE_HASH local=${LOCAL_HASH:-<none>}"

    if [ "$REMOTE_HASH" = "$LOCAL_HASH" ]; then
      echo "Mode is current."
    else
      echo "Mode changed, installing it."
      mkdir -p gamemodes
      cp -f "$REMOTE_LUA" "$LOCAL_LUA"
      echo "mode installed: $(sha_of "$LOCAL_LUA")"
    fi

    # UI: exact mirror of the repo folder every boot (drops leftovers and nesting)
    rm -rf ./gamemodes/feudalwars
    mkdir -p ./gamemodes/feudalwars
    cp -rf "$SRC_DIR"/gamemodes/feudalwars/. ./gamemodes/feudalwars/
    (cd "$SRC_DIR" && find gamemodes/feudalwars -type f | sort > "$UPDTMP/git_ui.txt")
    (cd ./gamemodes && find feudalwars -type f | sort > "$UPDTMP/disk_ui.txt")
    if diff "$UPDTMP/git_ui.txt" "$UPDTMP/disk_ui.txt" >/dev/null; then
      echo "UI in sync with git."
    else
      echo "UI drift (disk vs git):"
      diff "$UPDTMP/git_ui.txt" "$UPDTMP/disk_ui.txt" || true
    fi

    # the starter refreshes itself too
    cp -f "$SRC_DIR"/pterodactyl-start.sh ./start.sh.new && mv -f ./start.sh.new ./start.sh && chmod +x ./start.sh
    echo "Sync done."
  else
    echo "WARNING: sync download failed, starting the local build as it stands."
  fi
  rm -rf "$UPDTMP"
fi

export DOTNET_ROOT="$PWD/dotnet" DOTNET_ROOT_X64="$PWD/dotnet"

if [ -f gamemodes/feudalwars.lua ]; then
  echo "mode: $(wc -c < gamemodes/feudalwars.lua) bytes, $(wc -l < gamemodes/feudalwars.lua) lines"
else
  echo "WARNING: gamemodes/feudalwars.lua is missing"
fi

exec ./KcdMp.Server --config server.toml --gamemode gamemodes/feudalwars.lua