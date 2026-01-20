# Homestead Minecraft Server
# Based on: https://github.com/cramt/minecraft-homestead-docker
# Server Pack: https://github.com/CozyCord/homestead/wiki/Server-Pack

FROM ubuntu AS downloader
WORKDIR /app
RUN apt update -y && apt install curl unzip -y

# Download Homestead Server Pack 1.2.9.2 from Google Drive
ARG GDRIVE_FILE_ID=1KrsOqyAzhqMI3cn5eZxtJGdksWY6nDPr
RUN curl -L "https://drive.usercontent.google.com/download?id=${GDRIVE_FILE_ID}&export=download&confirm=t" --output pack.zip
RUN unzip pack.zip && \
    mv Homestead*/* . && \
    rmdir Homestead* && \
    rm -rf pack.zip

# Accept EULA and configure for containerized environment
RUN echo "eula=true" >> eula.txt
RUN sed -i -e 's/RESTART=true/RESTART=false/g' variables.txt
RUN sed -i -e 's/WAIT_FOR_USER_INPUT=true/WAIT_FOR_USER_INPUT=false/g' variables.txt

FROM eclipse-temurin:17
WORKDIR /data
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
COPY --from=downloader /app/ /app/
RUN chmod +x /app/start.sh || true
EXPOSE 25565
CMD ["/entrypoint.sh"]
