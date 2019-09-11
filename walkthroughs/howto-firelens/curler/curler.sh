#!/usr/bin/env bash

SLEEP_TIME=${SLEEP_TIME:-5}

while true; do
    sleep $SLEEP_TIME
    curl -vvv ${URL}
done
