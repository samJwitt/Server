#!/bin/sh
set -e

cd /opt/lostcity/engine

# a fresh bind mount hides the image's save/players, and data/players is a symlink into it
mkdir -p /opt/lostcity/save/players

# creates db.sqlite in save/ on first start, and applies any new migrations after an image update
node node_modules/prisma/build/index.js migrate deploy --schema prisma/singleworld/schema.prisma

# exec so the engine gets SIGTERM directly and can save players before exiting
exec node --import tsx src/app.ts
