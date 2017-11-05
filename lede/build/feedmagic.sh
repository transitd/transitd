#!/usr/bin/env sh
# back up config file because package updates may modify it
cp .config .config.feedmagic.bak

./scripts/feeds update -a
./scripts/feeds install -p transitd -a
./scripts/feeds install -a

# restore config file
cp .config.feedmagic.bak .config
