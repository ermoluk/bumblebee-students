#!/bin/bash
HOTSPOT_CONN="bumblebee-hotspot"
CHECK_INTERVAL=5
RECONNECT_INTERVAL=60
RECONNECT_ATTEMPTS=10      # how many times to try rejoining a known wifi before hotspot
RECONNECT_TRY_INTERVAL=6   # seconds between attempts (10 x 6 ~= 60s before hotspot)

log() { echo "$(date): $1" >> /tmp/wifi-manager.log 2>/dev/null || true; }

log "wifi_watchdog started"

last_reconnect=0
hotspot_starting=0

while true; do
    CONN=$(nmcli -t -f DEVICE,CONNECTION device status 2>/dev/null | grep "^wlan0:" | cut -d: -f2)
    STATE=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^wlan0:" | cut -d: -f2)

    if [ "$CONN" = "$HOTSPOT_CONN" ]; then
        hotspot_starting=0
        now=$(date +%s)
        if [ $((now - last_reconnect)) -ge $RECONNECT_INTERVAL ]; then
            last_reconnect=$now
            nmcli dev wifi rescan 2>/dev/null
            sleep 3
            VISIBLE=$(nmcli -t -f SSID dev wifi list 2>/dev/null | sort -u)
            KNOWN=$(nmcli -t -f NAME,TYPE con show 2>/dev/null | grep "802-11-wireless" | cut -d: -f1 | grep -v "^$HOTSPOT_CONN$")
            for name in $KNOWN; do
                SSID=$(nmcli -t -f 802-11-wireless.ssid con show "$name" 2>/dev/null | cut -d: -f2)
                [ -z "$SSID" ] && SSID="$name"
                if echo "$VISIBLE" | grep -qF "$SSID"; then
                    log "known network '$SSID' visible, switching from hotspot"
                    nmcli connection down "$HOTSPOT_CONN" 2>/dev/null
                    nmcli connection modify "$name" connection.autoconnect yes 2>/dev/null
                    nmcli connection up "$name" 2>/dev/null && log "connected to $SSID" || log "failed to connect to $SSID"
                    break
                fi
            done
        fi
        sleep $CHECK_INTERVAL
        continue
    fi

    # Reset autoconnect for all known wifi connections
    nmcli -t -f NAME,TYPE con show 2>/dev/null | grep "802-11-wireless" | cut -d: -f1 | while read name; do
        [ "$name" = "$HOTSPOT_CONN" ] && continue
        nmcli connection modify "$name" connection.autoconnect yes 2>/dev/null
    done

    # wlan0 not connected and not already on the hotspot:
    # actively try to rejoin a known wifi RECONNECT_ATTEMPTS times, raise hotspot only if all fail.
    # Never reboots — this is the sole path on wifi loss (boot-time AND in-flight).
    if [ "$STATE" != "connected" ] && [ "$hotspot_starting" -eq 0 ]; then
        CLIENT_CONN=$(nmcli -t -f NAME,TYPE con show 2>/dev/null | grep "802-11-wireless" | cut -d: -f1 | grep -v "^$HOTSPOT_CONN$" | head -1)
        log "wlan0 not connected (state=$STATE), reconnect loop to ${CLIENT_CONN:-<none>}"
        reconnected=0
        for i in $(seq 1 "$RECONNECT_ATTEMPTS"); do
            [ -n "$CLIENT_CONN" ] && nmcli connection up "$CLIENT_CONN" 2>/dev/null
            sleep "$RECONNECT_TRY_INTERVAL"
            ST=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^wlan0:" | cut -d: -f2)
            if [ "$ST" = "connected" ]; then
                log "reconnected on attempt $i"
                reconnected=1
                break
            fi
            log "reconnect attempt $i/$RECONNECT_ATTEMPTS failed"
        done
        if [ "$reconnected" -eq 0 ]; then
            RAND=$((RANDOM % 9000 + 1000))
            SSID="Bumblebee-${RAND}"
            log "reconnect failed after $RECONNECT_ATTEMPTS attempts, activating hotspot $SSID"
            nmcli connection modify "$HOTSPOT_CONN" wifi.ssid "$SSID" 2>/dev/null
            hotspot_starting=1
            nmcli connection up "$HOTSPOT_CONN" 2>/dev/null && log "hotspot up: $SSID" || { log "ERROR: hotspot failed"; hotspot_starting=0; }
        fi
    fi

    sleep $CHECK_INTERVAL
done
