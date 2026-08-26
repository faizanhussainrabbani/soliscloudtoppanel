#!/bin/sh
# Prints the function's variables in KEY=value form, ready to paste into
# Appwrite -> Functions -> Settings -> Variables.
#
#   sh scripts/print-env.sh
#
# WARNING: prints real secrets to your terminal — the SolisCloud session cookie
# and the signing secret. Don't screenshot it or paste it into a chat. It exists
# so those values never have to be retyped by hand.
#
# The SOLIS_* values come from the macOS app's UserDefaults. The three Appwrite
# IDs come from ids.local (gitignored), because they are account-specific and
# this project keeps nothing account-specific in source — the same reason the
# station ID and signing secret were moved out of SolisSettings. Create it from
# ids.local.example once.

D=com.faizan.SolisSolarMonitor
get() { defaults read "$D" "$1" 2>/dev/null; }

DIR=$(dirname "$0")
if [ -f "$DIR/ids.local" ]; then
  . "$DIR/ids.local"
else
  echo "# scripts/ids.local not found — copy scripts/ids.local.example and fill it in." >&2
fi

cat <<VARS
SOLIS_STATION_ID=$(get station-id)
SOLIS_COOKIE=$(get cookie)
SOLIS_DEVICE_ID=$(get device-id)
SOLIS_SIGNING_SECRET=$(get api-signing-secret)
APPWRITE_DATABASE_ID=${APPWRITE_DATABASE_ID:-<from console: Databases -> your database>}
APPWRITE_TABLE_ID=${APPWRITE_TABLE_ID:-<from console: the table ID>}
ALERT_USER_IDS=${ALERT_USER_IDS:-<from console: Auth -> Users -> user ID>}
VARS
