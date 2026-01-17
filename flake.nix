{
  description = "Minecraft Servers - Docker-based modded Minecraft servers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
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
      });
}
