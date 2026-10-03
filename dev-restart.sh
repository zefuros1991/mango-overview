#!/bin/sh
# Restart the overview service (development helper). $1 = launcher to use.
launcher=${1:-$(dirname "$(readlink -f "$0")")/bin/mango-overview}
for pid in $(pgrep -x qs); do
	case "$(tr '\0' ' ' < /proc/$pid/cmdline)" in *mango-overview/overview*) kill "$pid" ;; esac
done
sleep 0.5
setsid "$launcher" > "${MANGO_OVERVIEW_LOG:-/dev/null}" 2>&1 < /dev/null &
