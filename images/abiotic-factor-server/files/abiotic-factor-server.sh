#!/usr/bin/env bash

set -euo pipefail
shopt -s inherit_errexit

SERVER_BIN="${SERVER_DIR:-"/home/steam/.local/share/Steam/steamapps/common/Abiotic Factor Dedicated Server"}/AbioticFactor/Binaries/Win64/AbioticFactorServer-Win64-Shipping.exe"

# --- Check binary ---

if [[ ! -e $SERVER_BIN ]]; then
	echo "Could not find server binary $SERVER_BIN"
	exit 1
fi

# --- Setup server args ---

args=()

[[ -n ${MAX_PLAYERS:-} ]] && args+=("-MaxServerPlayers=${MAX_PLAYERS}")
[[ -n ${PORT:-} ]] && args+=("-PORT=${PORT}")
[[ -n ${QUERY_PORT:-} ]] && args+=("-QUERYPORT=${QUERY_PORT}") # cSpell:ignore QUERYPORT
[[ -n ${SERVER_PASSWORD:-} ]] && args+=("-ServerPassword=${SERVER_PASSWORD}")
[[ -n ${SERVER_NAME:-} ]] && args+=("-SteamServerName=${SERVER_NAME}")
[[ -n ${SAVE_NAME:-} ]] && args+=("-WorldSaveName=${SAVE_NAME}")
[[ -n ${ADDITIONAL_ARGS:-} ]] && args+=("${ADDITIONAL_ARGS}")

case "${USE_PERF_THREADS:-false}" in
true | 1 | yes | on)
	args+=("-useperfthreads") # cSpell:ignore useperfthreads
	;;
esac

case "${NO_ASYNC_LOADING_THREAD}" in
true | 1 | yes | on)
	args+=("-NoAsyncLoadingThread")
	;;
esac

# --- Start server ---

wine64 "$SERVER_BIN" "${args[@]}"
