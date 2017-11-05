#!/usr/bin/env sh
# see https://dev.openwrt.org/ticket/20821
patch --force --no-backup-if-mismatch -p1 -i lnum.nuke.patch
