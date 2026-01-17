# D&J Minecraft Server with NeoForge modpack
# Uses itzg/minecraft-server with built-in packwiz support
FROM itzg/minecraft-server:java21

LABEL org.opencontainers.image.source="https://github.com/curtbushko/minecraft-servers"
LABEL org.opencontainers.image.description="D&J Minecraft Server with NeoForge modpack"
LABEL org.opencontainers.image.licenses="MIT"

# Server type and versions
ENV TYPE=NEOFORGE
ENV VERSION=1.21.1
ENV NEOFORGE_VERSION=21.1.217

# Required: Accept Minecraft EULA
ENV EULA=TRUE

# Packwiz URL - set at build time, points to GitHub Pages
# The itzg image automatically filters out client-only mods
ARG PACKWIZ_URL
ENV PACKWIZ_URL=${PACKWIZ_URL}

# Default server settings (can be overridden at runtime)
ENV MEMORY=4G
ENV MAX_PLAYERS=20
ENV VIEW_DISTANCE=12
ENV SIMULATION_DISTANCE=8
ENV DIFFICULTY=normal
ENV MODE=survival
ENV ENABLE_COMMAND_BLOCK=true
ENV SPAWN_PROTECTION=0
