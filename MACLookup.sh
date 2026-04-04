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
DB=(
"Amcrest Technologies|9C:8E:CD,A0:60:32"
"Thingino(Cinnado)|02:07:25"
)

# ---- FUNCTIONS ----

show_usage() {
    echo "USAGE:"
    echo "  $0 <MAC1,MAC2,...>"
    echo
    echo "DESCRIPTION:"
    echo "  Lookup vendor names from MAC addresses using:"
    echo "    1) Local prefix database"
    echo "    2) Nmap database (if enabled)"
    echo "    3) Cache file (if enabled)"
    echo "    4) Online lookup (if enabled)"
    echo
    echo "EXAMPLE:"
    echo "  $0 9C:8E:CD:27:0C:B3,A0:60:32:03:61:33"
}

init_cache() {
    if [ "$ENABLE_CACHE_FILE" != "y" ]; then
        return
    fi

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
    local prefix="$1"

    for ENTRY in "${DB[@]}"; do
        NAME="${ENTRY%%|*}"
        PREFIXES="${ENTRY#*|}"

        IFS=',' read -ra PLIST <<< "$PREFIXES"

        for P in "${PLIST[@]}"; do
            if [ "$prefix" = "$P" ]; then
                echo "$NAME"
                return
            fi
        done
    done
}

lookup_nmap() {
    local mac="$1"

    if [ "$ENABLE_NMAP_LOOKUP" != "y" ] || [ ! -f "$NMAP_DB" ]; then
        return
    fi

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

    if [ "$ENABLE_CACHE_FILE" != "y" ]; then
        return
    fi

    grep -i "^$prefix|" "$CACHE_FILE" | head -n1 | cut -d'|' -f2
}

lookup_online() {
    local prefix="$1"

    if [ "$ENABLE_ONLINE_LOOKUP" != "y" ]; then
        return
    fi

    PREFIX_CLEAN=$(echo "$prefix" | tr -d ':')
    ONLINE=$(curl -s --max-time "$CURL_TIMEOUT" "https://api.macvendors.com/$PREFIX_CLEAN")

    if echo "$ONLINE" | grep -qi 'errors'; then
        return
    fi

    echo "$ONLINE"

    if [ "$ENABLE_CACHE_FILE" = "y" ]; then
        if ! grep -iq "^$prefix|" "$CACHE_FILE"; then
            echo "$prefix|$ONLINE" >> "$CACHE_FILE"
        fi
    fi
}

# ---- MAIN ----

# Help flags
case "$1" in
    -h|--help|-?)
        show_usage
        exit 0
        ;;
esac

if [ -z "$1" ]; then
    show_usage
    exit 1
fi

init_cache

IFS=',' read -ra MACS <<< "$1"

for RAWMAC in "${MACS[@]}"; do

    MAC=$(normalize_mac "$RAWMAC")
    PREFIX=$(get_prefix "$MAC")

    FOUND=""

    # 1. Local
    FOUND=$(lookup_local_db "$PREFIX")
    if [ -n "$FOUND" ]; then
        echo "$MAC -> $FOUND"
        continue
    fi

    # 2. Nmap
    FOUND=$(lookup_nmap "$MAC")
    if [ -n "$FOUND" ]; then
        echo "$MAC -> ($FOUND)"
        continue
    fi

    # 3. Cache
    FOUND=$(lookup_cache "$PREFIX")
    if [ -n "$FOUND" ]; then
        echo "$MAC -> ($FOUND)"
        continue
    fi

    # 4. Online
    FOUND=$(lookup_online "$PREFIX")
    if [ -n "$FOUND" ]; then
        echo "$MAC -> ($FOUND)"
    else
        echo "$MAC -> (unknown)"
    fi

done
