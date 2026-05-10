#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
openssl genrsa -out certs/responder.key 2048
openssl req -new -x509 -days 3650 -key certs/responder.key -out certs/responder.crt -subj "/"
