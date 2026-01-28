# Homestead Minecraft Server
# Uses packwiz for mod management - same mods as client
# Server Pack: https://github.com/CozyCord/homestead/wiki/Server-Pack

FROM itzg/minecraft-server:java17

# Minecraft and mod loader configuration
ENV TYPE=FABRIC
ENV VERSION=1.20.1
ENV FABRIC_LOADER_VERSION=0.17.2
ENV EULA=TRUE

# Memory settings (can be overridden at runtime)
ENV MEMORY=6G

# Packwiz URL for automatic mod downloading
# The itzg/minecraft-server image will automatically filter out client-only mods
ARG PACKWIZ_URL
ENV PACKWIZ_URL=${PACKWIZ_URL}

# Server properties
ENV MAX_PLAYERS=20
ENV MOTD="Homestead Minecraft Server"
ENV DIFFICULTY=normal
ENV VIEW_DISTANCE=12
ENV SIMULATION_DISTANCE=10

EXPOSE 25565
