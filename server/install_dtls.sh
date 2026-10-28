#!/bin/sh
# Makes the server's DTLS key and certificate (rev 42's encryption).
# Run once on the box, by hand:   sudo sh install_dtls.sh
# Rotating later:                 sudo sh install_dtls.sh --rotate
#
# Touches only /etc/psykinetic/dtls.* (or dtls.next.* with --rotate).
# The key is never printed. The unit hands it to the server as a systemd
# credential (LoadCredential in psykinetic.service), so the service user
# never reads the file itself.
# Printed: the certificate's SHA-256 fingerprint and the certificate
# (public: it goes in the client as net/dtls/pinned.crt).
#
# A rotation: --rotate writes dtls.next.key/.crt; a client cut pins both
# certificates; then, at the box swap, by hand:
#   sudo mv /etc/psykinetic/dtls.next.key /etc/psykinetic/dtls.key
#   sudo mv /etc/psykinetic/dtls.next.crt /etc/psykinetic/dtls.crt
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
if [ -e "$dir/$name.key" ]; then
	echo "$dir/$name.key already exists; nothing changed"; exit 1
fi
key="$dir/$name.key.new"
crt="$dir/$name.crt.new"
trap 'rm -f "$key" "$crt"' EXIT
umask 077
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
	-subj /CN=psykinetic -keyout "$key" -out "$crt"
chown root:root "$key" "$crt"
chmod 600 "$key"
chmod 644 "$crt"
mv "$crt" "$dir/$name.crt"
mv "$key" "$dir/$name.key"
openssl x509 -in "$dir/$name.crt" -noout -fingerprint -sha256
cat "$dir/$name.crt"
