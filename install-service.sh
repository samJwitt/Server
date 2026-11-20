#!/bin/bash
# Installs lostcity.service: systemd runs the image with docker compose, and the host keeps only
#   /etc/lostcity/docker-compose.yml   (copied from next to this script)
#   /srv/lostcity/save                 (db.sqlite and player saves)
#
# Nothing from this repo needs to stay on the host, e.g.:
#   scp install-service.sh docker-compose.yml root@host:/tmp/ && ssh root@host /tmp/install-service.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
	echo You must run this as root
	exit 1
fi

if ! command -v docker >/dev/null; then
	echo You must install Docker to proceed: https://docs.docker.com/engine/install/debian/
	exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
	echo You must install the Docker Compose plugin to proceed: apt install docker-compose-plugin
	exit 1
fi

src="$(cd "$(dirname "$0")" && pwd)"
docker="$(command -v docker)"

install -d -m 755 /etc/lostcity
install -m 644 "$src/docker-compose.yml" /etc/lostcity/docker-compose.yml
# the host has no build context, so only ever pull
sed -i '/^    build: \.$/d' /etc/lostcity/docker-compose.yml

# docker would create this as root, but the container runs as uid 1000
mkdir -p /srv/lostcity/save/players
# copy (not move) saves from the old launcher layout, the first time only
old=/srv/lostcity/game/save
if [ -d "$old" ] && [ ! -e /srv/lostcity/save/db.sqlite ]; then
	echo "Copying existing saves from $old"
	cp -a "$old"/. /srv/lostcity/save/
fi
chown -R 1000:1000 /srv/lostcity/save

cat > /etc/systemd/system/lostcity.service <<EOF
[Unit]
Description=Lost City server
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/etc/lostcity
# runs in the foreground so systemd tracks the container and journald gets its output
ExecStart=$docker compose up --no-log-prefix --abort-on-container-exit
ExecStop=$docker compose down
Restart=on-failure
RestartSec=10
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable lostcity.service

echo
echo "Installed lostcity.service (enabled, not started)."
echo
echo "  systemctl start lostcity              start it"
echo "  journalctl -u lostcity -f             watch the server"
echo "  cd /etc/lostcity && docker compose pull && systemctl restart lostcity   update"
echo
echo "  /srv/lostcity/save                    db.sqlite and players/ - back this up"
