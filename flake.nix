{
  description = "Minecraft Servers - Docker-based modded Minecraft servers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Server configurations - add new servers here
      servers = {
        dj-server = {
          name = "D&J Minecraft Server";
          minecraft = "1.21.1";
          loader = "neoforge";
          loaderVersion = "21.1.217";
          packwizUrl = "https://curtbushko.github.io/minecraft-servers/dj-server/pack.toml";
        };
        # Add more servers as needed:
        # another-server = {
        #   name = "Another Server";
        #   minecraft = "1.21.1";
        #   loader = "neoforge";
        #   loaderVersion = "21.1.217";
        #   packwizUrl = "https://curtbushko.github.io/minecraft-servers/another-server/pack.toml";
        # };
      };

      # packwiz-installer-bootstrap JAR
      packwizBootstrap = pkgs: pkgs.fetchurl {
        url = "https://github.com/packwiz/packwiz-installer-bootstrap/releases/download/v0.0.3/packwiz-installer-bootstrap.jar";
        sha256 = "sha256-qPuyTcYEJ46X9GiOgtPZGjGLmO/AjV2/y8vKtkQ9EWw=";
      };

      # Home-manager module for Prism Launcher instances
      homeManagerModule = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.minecraft-servers;
          bootstrap = packwizBootstrap pkgs;
        in
        {
          options.programs.minecraft-servers = {
            enable = lib.mkEnableOption "Minecraft server modpack instances for Prism Launcher";

            enabledServers = lib.mkOption {
              type = lib.types.listOf (lib.types.enum (builtins.attrNames servers));
              default = builtins.attrNames servers;
              description = "List of servers to create instances for";
              example = [ "dj-server" ];
            };

            instancesPath = lib.mkOption {
              type = lib.types.str;
              default = "${config.home.homeDirectory}/.local/share/PrismLauncher/instances";
              description = "Path to Prism Launcher instances directory";
            };

            javaPackage = lib.mkOption {
              type = lib.types.package;
              default = pkgs.openjdk21;
              description = "Java package to use for running packwiz-installer";
            };
          };

          config = lib.mkIf cfg.enable {
            # Ensure Prism Launcher is installed
            home.packages = [ pkgs.prismlauncher cfg.javaPackage ];

            # Create instance directories and configs
            home.file = lib.mkMerge (map
              (serverName:
                let
                  server = servers.${serverName};
                  instanceDir = "${cfg.instancesPath}/${serverName}";
                in
                {
                  # packwiz-installer-bootstrap.jar in .minecraft folder
                  "${instanceDir}/.minecraft/packwiz-installer-bootstrap.jar".source = bootstrap;

                  # Instance configuration
                  "${instanceDir}/instance.cfg".text = ''
                    [General]
                    ConfigVersion=1.2
                    iconKey=default
                    name=${server.name}
                    OverrideCommands=true
                    PreLaunchCommand="$INST_JAVA" -jar packwiz-installer-bootstrap.jar ${server.packwizUrl}
                  '';

                  # Component versions (mmc-pack.json)
                  "${instanceDir}/mmc-pack.json".text = builtins.toJSON {
                    components = [
                      {
                        cachedName = "LWJGL 3";
                        cachedVersion = "3.3.3";
                        dependencyOnly = true;
                        uid = "org.lwjgl3";
                        version = "3.3.3";
                      }
                      {
                        cachedName = "Minecraft";
                        cachedRequires = [{ equals = "3.3.3"; uid = "org.lwjgl3"; }];
                        cachedVersion = server.minecraft;
                        important = true;
                        uid = "net.minecraft";
                        version = server.minecraft;
                      }
                    ] ++ (if server.loader == "neoforge" then [
                      {
                        cachedName = "NeoForge";
                        cachedRequires = [{ equals = server.minecraft; uid = "net.minecraft"; }];
                        cachedVersion = server.loaderVersion;
                        uid = "net.neoforged";
                        version = server.loaderVersion;
                      }
                    ] else if server.loader == "fabric" then [
                      {
                        cachedName = "Intermediary Mappings";
                        cachedRequires = [{ equals = server.minecraft; uid = "net.minecraft"; }];
                        cachedVersion = server.minecraft;
                        dependencyOnly = true;
                        uid = "net.fabricmc.intermediary";
                        version = server.minecraft;
                      }
                      {
                        cachedName = "Fabric Loader";
                        cachedRequires = [{ uid = "net.fabricmc.intermediary"; }];
                        cachedVersion = server.loaderVersion;
                        uid = "net.fabricmc.fabric-loader";
                        version = server.loaderVersion;
                      }
                    ] else if server.loader == "forge" then [
                      {
                        cachedName = "Forge";
                        cachedRequires = [{ equals = server.minecraft; uid = "net.minecraft"; }];
                        cachedVersion = server.loaderVersion;
                        uid = "net.minecraftforge";
                        version = server.loaderVersion;
                      }
                    ] else []);
                    formatVersion = 1;
                  };
                })
              cfg.enabledServers);
          };
        };

    in
    {
      # Export the home-manager module
      homeManagerModules.default = homeManagerModule;
      homeManagerModules.minecraft-servers = homeManagerModule;

      # Export server configurations for external use
      lib.servers = servers;
    }
    //
    # Per-system outputs (devShell)
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          name = "minecraft-servers";

          buildInputs = with pkgs; [
            # Core tools
            docker

            # Go (for installing packwiz)
            go

            # Script dependencies
            curl
            jq
            gnused
            coreutils
            findutils
            bash

            # GitHub CLI (for releases and PR management)
            gh

            # Java for running packwiz-installer locally (testing client sync)
            openjdk21
          ];

          shellHook = ''
            echo ""
            echo "Minecraft Servers Development Environment"
            echo "=========================================="
            echo ""

            # Add go bin to path
            export PATH="$HOME/go/bin:$PATH"

            # Ensure packwiz is available
            if ! command -v packwiz &> /dev/null; then
              echo "Installing packwiz..."
              go install github.com/packwiz/packwiz@latest
            fi

            echo "Available commands:"
            echo "  ./scripts/build.sh <server>           Build Docker image"
            echo "  ./scripts/push.sh <server>            Push to ghcr.io"
            echo "  ./scripts/packwiz-update.sh <server>  Update mods"
            echo ""
            echo "Packwiz commands (run from servers/<name>/):"
            echo "  packwiz modrinth add <mod>      Add mod from Modrinth"
            echo "  packwiz update --all            Update all mods"
            echo "  packwiz refresh                 Refresh index"
            echo ""
          '';
        };

        # Package that creates a script to manually set up instances
        packages.setup-instances = pkgs.writeShellScriptBin "setup-minecraft-instances" ''
          set -e
          INSTANCES_DIR="''${1:-$HOME/.local/share/PrismLauncher/instances}"
          BOOTSTRAP_JAR="${packwizBootstrap pkgs}"

          echo "Setting up Minecraft server instances in $INSTANCES_DIR"

          ${builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (name: server: ''
            echo "Creating instance: ${name}"
            mkdir -p "$INSTANCES_DIR/${name}/.minecraft"
            cp "$BOOTSTRAP_JAR" "$INSTANCES_DIR/${name}/.minecraft/packwiz-installer-bootstrap.jar"

            cat > "$INSTANCES_DIR/${name}/instance.cfg" << 'EOF'
          [General]
          ConfigVersion=1.2
          iconKey=default
          name=${server.name}
          OverrideCommands=true
          PreLaunchCommand="$INST_JAVA" -jar packwiz-installer-bootstrap.jar ${server.packwizUrl}
          EOF

            cat > "$INSTANCES_DIR/${name}/mmc-pack.json" << 'EOF'
          ${builtins.toJSON {
            components = [
              { cachedName = "LWJGL 3"; cachedVersion = "3.3.3"; dependencyOnly = true; uid = "org.lwjgl3"; version = "3.3.3"; }
              { cachedName = "Minecraft"; cachedRequires = [{ equals = "3.3.3"; uid = "org.lwjgl3"; }]; cachedVersion = server.minecraft; important = true; uid = "net.minecraft"; version = server.minecraft; }
            ] ++ (if server.loader == "neoforge" then [
              { cachedName = "NeoForge"; cachedRequires = [{ equals = server.minecraft; uid = "net.minecraft"; }]; cachedVersion = server.loaderVersion; uid = "net.neoforged"; version = server.loaderVersion; }
            ] else []);
            formatVersion = 1;
          }}
          EOF
            echo "  Created ${name} instance"
          '') servers))}

          echo ""
          echo "Done! Restart Prism Launcher to see the new instances."
        '';
      });
}
