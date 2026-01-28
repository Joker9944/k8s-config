#!/usr/bin/env bash

set -euo pipefail
shopt -s inherit_errexit

STEAM_ROOT="$HOME/.local/share/Steam"
if [ ! -e "$HOME/.steam" ]; then
	mkdir -p "$HOME/.steam"
	ln -s "$STEAM_ROOT" "$HOME/.steam/root"
	ln -s "$STEAM_ROOT" "$HOME/.steam/steam"
fi

if [ ! -e "$STEAM_ROOT/steamcmd" ]; then
	mkdir -p "$STEAM_ROOT/steamcmd/linux32"
	# steamcmd will replace these files with newer ones itself on first run
	cp /lib/steamcmd/steamcmd.sh "$STEAM_ROOT/steamcmd/"
	cp /lib/steamcmd/linux32/steamcmd "$STEAM_ROOT/steamcmd/linux32/"
fi
exec "$STEAM_ROOT/steamcmd/steamcmd.sh" "$@"
