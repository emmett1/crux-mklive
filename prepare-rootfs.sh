#!/bin/sh

ROOTFS=$PWD/rootfs
mkdir -p $ROOTFS/var/lib/pkg
touch $ROOTFS/var/lib/pkg/db

pkg-get -r $ROOTFS install $(ports -l | grep ^core | awk -F / '{print $2}' | tr '\n' ' ')
pkg-get -r $ROOTFS depinst $(grep -Ev ^'(#|$)' packages.opt)
pkg-get -r $ROOTFS depinst $(grep -Ev ^'(#|$)' packages.xorg)
pkg-get -r $ROOTFS depinst $(grep -Ev ^'(#|$)' packages.custom)
