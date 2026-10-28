#!/bin/sh
# The server's credentials for 717 (DTLS, rev 42), made once on the box:
#   sudo sh install_dtls.sh            the DTLS key and certificate, and the token
#   sudo sh install_dtls.sh --rotate   a next key and certificate (see below)
#
# Touches only /etc/psykinetic/dtls.* (dtls.next.* with --rotate) and
# /etc/psykinetic/token. /etc/psykinetic/env is read for its PSYKINETIC_TOKEN
# line and never changed. The two steps are independent: each is skipped
# if its file is already there ("already there"), so a re-run finishes
# whatever a partial run left.
#
# The unit hands all three files to the server as systemd credentials
# (LoadCredential in psykinetic.service); the service user never reads them.
# Never printed: the key, the token. Printed: the certificate's SHA-256
# fingerprint and the certificate (public: the client pins it as
# net/dtls/pinned.crt).
#
# The token, from now on, lives in /etc/psykinetic/token (written without a
# trailing newline; the server trims whitespace anyway), and the server
# takes it before env's. To change it: edit /etc/psykinetic/token (sudo,
# keep it 0600 root:root) and restart psykinetic. Editing env's
# PSYKINETIC_TOKEN line changes nothing once this file is there.
#
# A DTLS rotation: --rotate writes dtls.next.key/.crt; a client cut pins both
# certificates; then, at the box swap, by hand:
#   sudo mv /etc/psykinetic/dtls.next.crt /etc/psykinetic/dtls.crt
#   sudo mv /etc/psykinetic/dtls.next.key /etc/psykinetic/dtls.key
#   sudo systemctl restart psykinetic
# and a later client cut drops the old certificate.
set -eu
dir=/etc/psykinetic
name=dtls
if [ "${1:-}" = "--rotate" ]; then
	name=dtls.next
fi
if [ "$(id -u)" != 0 ]; then
	echo "run with sudo"; exit 1
fi
if [ ! -d "$dir" ]; then
	echo "$dir does not exist (the server's env file lives there); nothing changed"; exit 1
fi
failed=0
umask 077
trap 'rm -f "$dir/$name.key.new" "$dir/$name.crt.new" "$dir/token.new"' EXIT

# --- the DTLS key and certificate ---------------------------------------------
if [ -e "$dir/$name.key" ]; then
	echo "dtls: $dir/$name.key already there"
else
	key="$dir/$name.key.new"
	crt="$dir/$name.crt.new"
	if openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
			-subj /CN=psykinetic -keyout "$key" -out "$crt"; then
		chown root:root "$key" "$crt"
		chmod 600 "$key"
		chmod 644 "$crt"
		mv "$crt" "$dir/$name.crt"
		mv "$key" "$dir/$name.key"
		echo "dtls: written"
	else
		echo "dtls: openssl failed; nothing written"
		failed=1
	fi
fi
if [ -e "$dir/$name.crt" ]; then
	openssl x509 -in "$dir/$name.crt" -noout -fingerprint -sha256
	cat "$dir/$name.crt"
fi

# --- the token, copied from env -----------------------------------------------
if [ -e "$dir/token" ]; then
	echo "token: already there"
else
	# The first PSYKINETIC_TOKEN= line, an "export " before it allowed; the
	# value without a CR, surrounding blanks or one pair of quotes. Held in a
	# variable only, never echoed.
	value="$(grep -m 1 -E '^[[:space:]]*(export[[:space:]]+)?PSYKINETIC_TOKEN=' "$dir/env" 2>/dev/null \
		| sed -e 's/^[^=]*=//' -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
			-e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/" || true)"
	if [ -z "$value" ]; then
		echo "token: none in env; nothing written"
		failed=1
	else
		printf '%s' "$value" > "$dir/token.new"
		chown root:root "$dir/token.new"
		chmod 600 "$dir/token.new"
		mv "$dir/token.new" "$dir/token"
		echo "token: copied"
	fi
	value=""
fi
exit "$failed"
