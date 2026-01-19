# Minecraft Servers

Docker-based Minecraft server modpacks using [packwiz](https://packwiz.infra.link/) and [itzg/minecraft-server](https://docker-minecraft-server.readthedocs.io/).

## Available Servers

| Server | Minecraft | Mod Loader | Description |
|--------|-----------|------------|-------------|
| [dj-server](./servers/dj-server/) | 1.21.1 | NeoForge 21.1.217 | D&J Minecraft Server Modpack |

## Quick Start

### Running a Server

```bash
docker run -d \
  -v ./data:/data \
  -p 25565:25565 \
  ghcr.io/curtbushko/minecraft-servers/dj-server:latest
```

With custom settings:

```bash
docker run -d \
  -e MEMORY=8G \
  -e MAX_PLAYERS=10 \
  -e DIFFICULTY=hard \
  -v ./data:/data \
  -p 25565:25565 \
  ghcr.io/curtbushko/minecraft-servers/dj-server:latest
```

### Client Setup (Auto-Sync)

Players can auto-sync mods using packwiz-installer:

1. Install [Prism Launcher](https://prismlauncher.org/) or MultiMC
2. Create a new instance with **NeoForge 21.1.217** for **Minecraft 1.21.1**
3. Download [packwiz-installer-bootstrap.jar](https://github.com/packwiz/packwiz-installer-bootstrap/releases)
4. Place it in your instance's `.minecraft` folder
5. Add a pre-launch command in instance settings:
   ```
   java -jar packwiz-installer-bootstrap.jar https://curtbushko.github.io/minecraft-servers/dj-server/pack.toml
   ```
6. Launch the game - mods will auto-sync on every start!

### Client Setup with Nix (Recommended)

This repository provides a Nix flake with a home-manager module that automatically configures Prism Launcher instances with auto-sync.

#### Option 1: Home-Manager Module

Add the flake to your home-manager configuration:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    minecraft-servers.url = "github:curtbushko/minecraft-servers";
  };

  outputs = { self, nixpkgs, home-manager, minecraft-servers, ... }: {
    homeConfigurations."your-username" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        minecraft-servers.homeManagerModules.default
        {
          programs.minecraft-servers = {
            enable = true;
            # Optional: only enable specific servers (defaults to all)
            enabledServers = [ "dj-server" ];
          };
        }
      ];
    };
  };
}
```

This will:
- Install Prism Launcher and Java 21
- Create pre-configured instances for each server
- Set up auto-sync via packwiz-installer on every launch

#### Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the module |
| `enabledServers` | list | all servers | Which server instances to create |
| `instancesPath` | string | `~/.local/share/PrismLauncher/instances` | Prism Launcher instances path |
| `javaPackage` | package | `pkgs.openjdk21` | Java package for packwiz-installer |
| `serverEntries` | list | `[]` | Servers to add to the multiplayer menu (see below) |

##### Pre-configured Server List

You can automatically add servers to Minecraft's multiplayer menu:

```nix
programs.minecraft-servers = {
  enable = true;
  serverEntries = [
    { name = "D&J Server (gamingrig)"; ip = "gamingrig:25565"; }
    { name = "Another Server"; ip = "mc.example.com"; }
  ];
};
```

This generates a `servers.dat` file in each instance's `.minecraft` folder with your pre-configured servers.

#### Option 2: One-Time Setup Script

If you're not using home-manager, you can use the setup script:

```bash
# Run directly from the flake
nix run github:curtbushko/minecraft-servers#setup-instances

# Or specify a custom instances path
nix run github:curtbushko/minecraft-servers#setup-instances -- ~/.local/share/PrismLauncher/instances
```

This creates the instance directories and configuration files in your Prism Launcher instances folder.

## Development

### Nix Development Environment

This repository uses a Nix flake for reproducible development:

```bash
# Enter the development shell
nix develop

# Or with direnv (recommended)
direnv allow
```

The dev shell provides:
- Docker
- Go (for packwiz installation)
- curl, jq, and other script dependencies
- GitHub CLI (`gh`)
- Java 21
- Automatically installs `packwiz` if not present

### Building Images Locally

```bash
# Build a specific server
./scripts/build.sh dj-server

# Build all servers
./scripts/build.sh --all

# Build and push
./scripts/build.sh dj-server --push
```

### Updating Mods

```bash
cd servers/dj-server

# Update all mods to latest compatible versions
../../scripts/packwiz-update.sh

# Dry run (preview changes)
../../scripts/packwiz-update.sh --dry-run
```

### Adding a New Server

1. Create a new directory:
   ```bash
   mkdir -p servers/my-server
   cd servers/my-server
   ```

2. Initialize packwiz:
   ```bash
   packwiz init --name "My Server" --mc-version 1.21.1 --modloader neoforge --modloader-version 21.1.217
   ```

3. Add mods:
   ```bash
   packwiz modrinth add sodium lithium create
   ```

4. Copy Dockerfile and server.env from an existing server and update values

5. Push - GitHub Actions handles building and publishing

## Architecture

### How Server-Side Filtering Works

The packwiz modpack contains ALL mods (client, server, and shared). The itzg/minecraft-server Docker image has built-in packwiz support that automatically:

1. Downloads `pack.toml` from the configured `PACKWIZ_URL`
2. Parses all `.pw.toml` mod files
3. **Filters out mods where `side = "client"`**
4. Downloads only `side = "both"` and `side = "server"` mods

This means:
- **Server**: Gets only server-compatible mods
- **Client**: Gets ALL mods (performance mods, shaders, minimaps, etc.)

### CI/CD

- **On push to `servers/`**: GitHub Actions builds and pushes Docker images to ghcr.io
- **On push to modpack files**: GitHub Pages deploys packwiz files for client auto-sync

### Repository Setup (for forks)

If you fork this repository, you need to configure GitHub Pages:

1. Go to **Settings > Pages**
2. Under "Build and deployment", set **Source** to **GitHub Actions**
3. The `pages.yml` workflow will now deploy packwiz files to `https://<username>.github.io/minecraft-servers/`

## License

MIT
