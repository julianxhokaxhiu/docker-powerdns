#!/bin/bash

WORKDIR="/etc"

# Create a backup of the original, if it doesn't exist
if ! [ -f "$WORKDIR/hosts.bak" ]; then
  cp "$WORKDIR/hosts" "$WORKDIR/hosts.bak"
fi

# Erase the current list
echo "" > "$WORKDIR/hosts"

# Read the list and fetch all the uncommented entries
while read line; do
  # Skip also blank lines
  if ! [[ $line = \#* ]] && [ ! -z $line ]; then
    curl -Ss $line >> "$WORKDIR/hosts"
  fi
done < "/root/ads.list"

# Finally restore previous entries
cat "$WORKDIR/hosts.bak" >> "$WORKDIR/hosts"

# Tell to the recursor to reload the hosts file
rec_control reload-zones
