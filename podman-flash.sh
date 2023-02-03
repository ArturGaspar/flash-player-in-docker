#!/bin/sh

set -eu


uid="$(id -u)"
gid="$(id -g)"

tag="firefox-flash-${uid}"

container_user=flash-user
container_home="/home/${container_user}"

podman build -t "${tag}" - <<EOF

FROM ubuntu:jammy

RUN apt-get update

RUN apt-get install -qy --no-install-recommends ca-certificates bzip2 wget

# Flash plugin.
RUN wget --no-check-certificate -O /tmp/flashplayer.tar.gz https://archive.org/download/flashplayerarchive/pub/flashplayer/installers/archive/fp_32.0.0.371_archive.zip/32_0_r0_371%2Fflashplayer32_0r0_371_linux.x86_64.tar.gz && \
    echo '62c1a22af9d3e8cf3f3a219100482d8e274343641bf575cfb312ba1ee50389fd  /tmp/flashplayer.tar.gz' | sha256sum -c && \
    mkdir -p /usr/lib/mozilla/plugins && \
    tar -C /usr/lib/mozilla/plugins -xf /tmp/flashplayer.tar.gz libflashplayer.so && \
    rm /tmp/flashplayer.tar.gz

# Flash plugin dependencies.
RUN apt-get install -qy --no-install-recommends \
    libasound2 \
    libasound2-plugins \
    libcurl4 \
    libgl1 \
    libgtk2.0-0 \
    libnspr4 \
    libnss3

# Firefox
RUN wget --no-check-certificate -O /tmp/firefox.tar.bz2 https://ftp.mozilla.org/pub/firefox/releases/78.15.0esr/linux-x86_64/en-US/firefox-78.15.0esr.tar.bz2 && \
    echo 'cf45a90b68a3f1cd7d7496792b85eb5e61b34718a752e54f4a849e46ce20f193  /tmp/firefox.tar.bz2' | sha256sum -c && \
    tar -C /opt -xf /tmp/firefox.tar.bz2 && \
    rm /tmp/firefox.tar.bz2

# Firefox dependencies.
RUN apt-get install -qy --no-install-recommends \
    libdbus-glib-1.2 \
    libgtk-3-0 \
    libpulse0 \
    libx11-xcb1 \
    libxt6

RUN ln -s 99-pulseaudio-default.conf.example /etc/alsa/conf.d/99-pulseaudio-default.conf

RUN groupmod -g "${gid}" users && \
    useradd -u "${uid}" -g users -d "${container_home}" "${container_user}"

EOF

host_home="${HOME}/.firefox-flash"

mkdir -p "${host_home}"

container_pulse_sock=/var/run/pulse.sock
host_pulse_sock="$(pactl info | head -n 1 | sed -n 's/^.*: \(.*\)$/\1/p')"

# X11 is required. On Wayland, Firefox disables Flash Player.
# See <https://bugzilla.mozilla.org/show_bug.cgi?id=1548475>.

podman run \
    -v /dev/dri:/dev/dri \
    -v /dev/shm:/dev/shm \
    -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
    -v "${host_home}:${container_home}" \
    -v "${XAUTHORITY}:${container_home}/.Xauthority:ro" \
    -v "$(xdg-user-dir DOWNLOAD):${container_home}/Downloads" \
    -v "${host_pulse_sock}:${container_pulse_sock}" \
    -e "DISPLAY=${DISPLAY}" \
    -e MOZ_DISABLE_CONTENT_SANDBOX=1 \
    -e "PULSE_SERVER=unix:${container_pulse_sock}" \
    -e "XAUTHORITY=${container_home}/.Xauthority" \
    -u "${container_user}" \
    --userns=keep-id \
    "${tag}" \
    /opt/firefox/firefox --no-remote
