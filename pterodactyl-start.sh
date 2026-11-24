#!/bin/bash
# Feudal Wars starter: checks GitHub for updates, then launches the server.
# Installed by the egg install script; refreshes itself from the repo too.
set -u
cd "$(dirname "$0")" || exit 1

REPO="lol1luv/kcd-mp-feudalwars"

mkdir -p tmp
export TMPDIR="$PWD/tmp" TMP="$PWD/tmp" TEMP="$PWD/tmp"

# Level override FIRST (before the update check): Wings sometimes fails to
# rewrite server.toml from the Startup variable, so enforce it here.
# LEVEL comes from the egg's Startup tab.
LEVEL_WANT="${LEVEL:-kutnohorsko}"
echo "LEVEL env = '${LEVEL:-<unset>}' -> want '$LEVEL_WANT'"
if [ -f server.toml ]; then
  echo "server.toml level before: $(grep -E '^[[:space:]]*level[[:space:]]*=' server.toml || echo '<none>')"
  if grep -qE '^[[:space:]]*level[[:space:]]*=' server.toml; then
    sed -i -E "s|^[[:space:]]*level[[:space:]]*=.*|level = \"$LEVEL_WANT\"|" server.toml
  else
    printf '\n[server]\nlevel = "%s"\n' "$LEVEL_WANT" >> server.toml
  fi
  echo "server.toml level after: $(grep -E '^[[:space:]]*level[[:space:]]*=' server.toml || echo '<none>')"
else
  echo "WARNING: no server.toml, server will use its own defaults."
fi

if [ "${AUTO_UPDATE:-1}" != "1" ]; then
  echo "Auto-update off (AUTO_UPDATE=${AUTO_UPDATE:-1}), starting local build."
else
  echo "Checking for Feudal Wars updates..."
  REMOTE_SHA=""
  if command -v curl >/dev/null 2>&1; then
    REMOTE_SHA="$(curl -sSL --max-time 15 "https://api.github.com/repos/$REPO/commits/main" 2>/dev/null | grep -oE '"sha": "[0-9a-f]{40}"' | head -1 | grep -oE '[0-9a-f]{40}')"
  fi
  LOCAL_SHA="$(cat .fw_version 2>/dev/null || echo "")"

  if [ -z "$REMOTE_SHA" ]; then
    echo "Update check skipped (GitHub unreachable), starting local build."
  elif [ "$REMOTE_SHA" = "$LOCAL_SHA" ]; then
    echo "Up to date ($REMOTE_SHA)."
  else
    echo "Updating ${LOCAL_SHA:-none} -> $REMOTE_SHA ..."
    UPDTMP="$PWD/tmp/update"
    rm -rf "$UPDTMP"
    mkdir -p "$UPDTMP"
    if curl -sSLf --max-time 180 "https://github.com/$REPO/archive/$REMOTE_SHA.tar.gz" -o "$UPDTMP/src.tar.gz" \
      && tar xzf "$UPDTMP/src.tar.gz" -C "$UPDTMP"; then
      SRC_DIR="$(find "$UPDTMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
      cp -f "$SRC_DIR"/KcdMp.Server ./KcdMp.Server
      cp -f "$SRC_DIR"/*.dll ./
      cp -f "$SRC_DIR"/*.so ./
      cp -f "$SRC_DIR"/KcdMp.Server.deps.json ./KcdMp.Server.deps.json
      cp -f "$SRC_DIR"/KcdMp.Server.runtimeconfig.json ./KcdMp.Server.runtimeconfig.json
      cp -f "$SRC_DIR"/server.toml.example ./server.toml.example
      cp -f "$SRC_DIR"/pterodactyl-start.sh ./start.sh.new
      mv -f ./start.sh.new ./start.sh
      mkdir -p gamemodes
      cp -f "$SRC_DIR"/gamemodes/feudalwars.lua ./gamemodes/feudalwars.lua
      # full sync of the UI folder: delete stale files (incl. nested feudalwars/feudalwars from the old cp bug), then copy exact
      rm -rf ./gamemodes/feudalwars
      mkdir -p ./gamemodes/feudalwars
      cp -rf "$SRC_DIR"/gamemodes/feudalwars/. ./gamemodes/feudalwars/
      # report drift: files on disk that git does not have (leftovers, manual edits)
      (cd "$SRC_DIR" && find gamemodes/feudalwars -type f | sort > "$UPDTMP/git_ui.txt")
      (cd ./gamemodes && find feudalwars -type f | sort > "$UPDTMP/disk_ui.txt")
      if ! diff "$UPDTMP/git_ui.txt" "$UPDTMP/disk_ui.txt" >/dev/null; then
        echo "UI drift (disk vs git):"
        diff "$UPDTMP/git_ui.txt" "$UPDTMP/disk_ui.txt" || true
      else
        echo "UI in sync with git."
      fi
      chmod +x KcdMp.Server start.sh
      echo "$REMOTE_SHA" > .fw_version
      echo "Updated to $REMOTE_SHA."
    else
      echo "WARNING: update download failed, starting local build."
    fi
    rm -rf "$UPDTMP"
  fi
fi

export DOTNET_ROOT="$PWD/dotnet" DOTNET_ROOT_X64="$PWD/dotnet"

exec ./KcdMp.Server --config server.toml --gamemode gamemodes/feudalwars.lua
