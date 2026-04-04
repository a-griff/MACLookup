#!/bin/bash
# -------------------------------------------------------
# MACLookup.sh
# Version: 1.0
# -------------------------------------------------------
# Description:
# Lookup manufacturer names based on MAC address prefixes.
# -------------------------------------------------------

# ---- SETTINGS ----
USE_ONLINE=1
CURL_TIMEOUT=3
ENABLE_NMAP_LOOKUP="y"   # <"y/n">
NMAP_DB="/usr/share/nmap/nmap-mac-prefixes"
ENABLE_CACHE_FILE="y"    # <"y/n">
CACHE_FILE="./maclookup.cache"
ENABLE_ONLINE_LOOKUP="y" # <"y/n">

# ---- PREFIX DATABASE ----
# SYNTAX:<NAME>|<MAC_PREFIX>
DB=(
"Amcrest Technologies|9C:8E:CD,A0:60:32"
"Cinnado|02:07:25"
)

# ---- FUNCTIONS ----

init_cache() {
    [ "$ENABLE_CACHE_FILE" != "y" ] && return

    if [ ! -f "$CACHE_FILE" ]; then
        {
            echo "# maclookup.cache"
            echo "# Created by: ./MACLookup.sh"
            echo "# Purpose: Cache MAC OUI prefix to vendor lookups"
        } > "$CACHE_FILE"
    fi

    sed -i '/errors/Id' "$CACHE_FILE"
}

normalize_mac() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

get_prefix() {
    echo "$1" | awk -F: '{printf "%s:%s:%s",$1,$2,$3}'
}

lookup_local_db() {
    local mac="$1"
    local best_match=""
    local best_len=0

    for ENTRY in "${DB[@]}"; do
        NAME="${ENTRY%%|*}"
        PREFIXES="${ENTRY#*|}"

        IFS=',' read -ra PLIST <<< "$PREFIXES"

        for P in "${PLIST[@]}"; do
            P=$(echo "$P" | tr '[:lower:]' '[:upper:]')

            if [[ "$mac" == "$P"* ]]; then
                LEN=${#P}

                if (( LEN > best_len )); then
                    best_len=$LEN
                    best_match="$NAME"
                fi
            fi
        done
    done

    [ -n "$best_match" ] && echo "$best_match"
}

lookup_nmap() {
    local mac="$1"

    [ "$ENABLE_NMAP_LOOKUP" != "y" ] && return
    [ ! -f "$NMAP_DB" ] && return

    HEX=$(echo "$mac" | tr -d ':')

    for LEN in 9 7 6; do
        KEY="${HEX:0:$LEN}"
        MATCH=$(grep -i "^$KEY[[:space:]]" "$NMAP_DB" | head -n1 | awk '{ $1=""; sub(/^ /,""); print }')

        if [ -n "$MATCH" ]; then
            echo "$MATCH"
            return
        fi
    done
}

lookup_cache() {
    local prefix="$1"

    [ "$ENABLE_CACHE_FILE" != "y" ] && return

    grep -i "^$prefix|" "$CACHE_FILE" | head -n1 | cut -d'|' -f2
}

lookup_online() {
    local prefix="$1"

    [ "$ENABLE_ONLINE_LOOKUP" != "y" ] && return

    PREFIX_CLEAN=$(echo "$prefix" | tr -d ':')
    ONLINE=$(curl -s --max-time "$CURL_TIMEOUT" "https://api.macvendors.com/$PREFIX_CLEAN")

    echo "$ONLINE" | grep -qi 'errors' && return

    echo "$ONLINE"

    if [ "$ENABLE_CACHE_FILE" = "y" ]; then
        if ! grep -iq "^$prefix|" "$CACHE_FILE"; then
            echo "$prefix|$ONLINE" >> "$CACHE_FILE"
        fi
    fi
}

# ---- MAIN ----

if [ -z "$1" ]; then
    echo "Usage: $0 <MAC1,MAC2,...>"
    exit 1
fi

init_cache

IFS=',' read -ra MACS <<< "$1"

for RAWMAC in "${MACS[@]}"; do

    MAC=$(normalize_mac "$RAWMAC")
    PREFIX=$(get_prefix "$MAC")

    FOUND=""

    FOUND=$(lookup_local_db "$MAC")
    if [ -n "$FOUND" ]; then
        echo "$MAC -> $FOUND"
        continue
    fi

    FOUND=$(lookup_nmap "$MAC")
    if [ -n "$FOUND" ]; then
        echo "$MAC -> ($FOUND)"
        continue
    fi

    FOUND=$(lookup_cache "$PREFIX")
    if [ -n "$FOUND" ]; then
        echo "$MAC -> ($FOUND)"
        continue
    fi

    FOUND=$(lookup_online "$PREFIX")
    if [ -n "$FOUND" ]; then
        echo "$MAC -> ($FOUND)"
    else
        echo "$MAC -> (unknown)"
    fi

done
