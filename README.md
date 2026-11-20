# KCD:MP Feudal Wars Server

A custom KCD:MP game mode with feudal houses, wars, and economy system.

## Features

- **Houses** - Create and join feudal houses
- **Wars** - Declare war, fight for score, win treasury bonuses
- **Economy** - Farming, crafting, taxes, upkeep
- **Prestige** - House status system
- **Taxes** - 10% of earnings go to house treasury
- **Upkeep** - 50 groschen/min per member from treasury

## Installation

### Pterodactyl Panel

1. Upload `panel.json` to your Pterodactyl panel as a new template
2. Create a new server using the Feudal Wars template
3. The panel will auto-configure the server

### Manual Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd linux

# Start the server
KcdMp.Server --config server.toml --gamemode gamemodes/feudalwars.lua
```

## Configuration

### server.toml

```toml
[server]
name = "Feudal Wars"
port = 7777
max_players = 32
level = "klaster"

[gamemode]
script = "gamemodes/feudalwars.lua"
watch = false

[commands]
builtin = true
public = ["help", "pos", "players", "items", "uptime", "house", "war", "money", "pay", "farm", "craft", "prestige", "taxes"]
```

### panel.json

Contains the Pterodactyl panel configuration for auto-deployment.

## Commands

### House Commands

- `/house create <name>` - Create a new house (3-16 letters, no spaces)
- `/house join <name>` - Join an existing house
- `/house leave` - Leave your house
- `/house list` - List all houses
- `/house info` - Information about your house

### War Commands

- `/war declare <house>` - Declare war (costs 5000 from treasury)
- `/war peace` - Ask for peace
- `/war status` - War status and scores

### Economy

- `/money` - Check your purse
- `/farm` - Earn 100 groschen (farming)
- `/craft` - Earn 150 groschen (crafting)
- `/pay <player> <amount>` - Pay another player (5% tax)
- `/prestige raise` - Raise house prestige (costs 10000)
- `/prestige info` - House prestige info
- `/taxes` - House treasury report

## How It Works

### Economy Flow

1. Players earn money via `/farm` and `/craft`
2. 10% tax goes to house treasury automatically
3. House pays upkeep: 50 groschen/min per member
4. Wars cost 5000 to declare
5. Prestige costs 10000 to raise

### Money Sinks (prevents "rich getting richer")

- War declaration cost: 5000 groschen
- Truce cost: 1000 groschen  
- Upkeep: 50/groschen per member/minute
- Prestige raise: 10000 groschen
- 10% tax on all player earnings

## Development

### Adding New Features

1. Edit `gamemodes/feudalwars.lua` for game logic
2. Edit `server.toml` for server config
3. Update `panel.json` for Pterodactyl panel changes

### Testing

```bash
# Start server for testing
KcdMp.Server --gamemode gamemodes/feudalwars.lua

# Connect with KCD:MP client
# Use /help to see available commands
```