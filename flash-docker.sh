#!/bin/sh

set -e

while getopts u: opt; do
    case "${opt}" in
        u)
            docker_user="$OPTARG"
            ;;
        ?)
            printf 'Usage: %s: [-u user]\n' "$0"
            exit 2
            ;;
    esac
done

if [ -n "${docker_user}" ]; then
    docker_cmd="sudo -u ${docker_user} -- docker"
else
    docker_cmd=docker
fi

uid="$(id -u)"
gid="$(id -g)"

tag="firefox-flash-${uid}"

$docker_cmd build -t "${tag}" - <<EOF

FROM ubuntu:focal

RUN apt-get update

RUN apt-get install -qy --no-install-recommends ca-certificates wget

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
    useradd -u "${uid}" -g users -d /home/user user

EOF

mkdir "${HOME}/.firefox-flash" || :

$docker_cmd run \
    -v /dev/shm:/dev/shm \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v "${HOME}/.firefox-flash:/home/user" \
    -v "$(xdg-user-dir DOWNLOAD):/home/user/Downloads" \
    -v "${XAUTHORITY}:/home/user/.Xauthority:ro" \
    -v "$(pactl info | head -n 1 | sed -n 's/^.*: \(.*\)$/\1/p'):/var/run/pulse.sock" \
    -e "DISPLAY=${DISPLAY}" \
    -e PULSE_SERVER=unix:/var/run/pulse.sock \
    -e XAUTHORITY=/home/user/.Xauthority \
    -u user \
    "${tag}" \
    /opt/firefox/firefox --no-remote
