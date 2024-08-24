#!/bin/bash -euo pipefail

if [ -z "$TGT_KUBECONFIG" ]; then
	echo "No kubeconfig specified" >&2
	exit 1
fi

function get_cert_from_kubeconfig() {
	grep client-certificate-data: $1 | \
		sed 's/^\s\+client-certificate-data:\s*//' | \
		base64 -d
}

function get_key_from_kubeconfig() {
	grep client-key-data: $1 | \
		sed 's/^\s\+client-key-data:\s*//' | \
		base64 -d
}

function generate_csr() {
	openssl x509 -x509toreq \
		-in			$1 \
		-signkey	$2 \
		-out		-  \
	| openssl req -out - # this trims off unblockable text preamble from some openssls
}

generate_csr <(get_cert_from_kubeconfig $TGT_KUBECONFIG) <(get_key_from_kubeconfig $TGT_KUBECONFIG)

