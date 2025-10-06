#!/bin/bash
set -e

LOGFILE=localyesconfig.log

# Backup current config
cp .config .config.old

# Run localyesconfig, capture all output
make localyesconfig > "$LOGFILE" 2>&1

# Extract newly enabled options as before
NEW_ENABLED=$(diff .config.old .config | grep '^> ' | sed 's/^> //' | grep '=y$' | cut -d= -f1)

# Enable those
echo "$NEW_ENABLED" | while IFS= read -r cfg; do
  if [ -n "$cfg" ]; then
    ./scripts/config --enable "$cfg" && echo "Enabled $cfg"
  fi
done

# Parse all missing config options, for example:
MISSING_CONFIGS=$(grep 'did not have configs CONFIG_' "$LOGFILE" | grep -o 'CONFIG_[A-Z0-9_]*' | sort -u)

echo "Enabling missing config options..."

for cfg in $MISSING_CONFIGS; do
  # Check if config option already set in .config
  if grep -q "^$cfg=" .config; then
    echo "Updating existing $cfg to =y"
    # Use sed to replace existing line directly
    sed -i "s/^$cfg=.*/$cfg=y/" .config
  else
    echo "Appending new $cfg=y"
    # Append the option at end of .config
    echo "$cfg=y" >> .config
  fi
done

echo "Finalizing config with make oldconfig..."
yes "" | make oldconfig
