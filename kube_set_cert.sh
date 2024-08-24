#!/bin/bash -euo pipefail

if [ -z "$TGT_KUBECONFIG" ]; then
	echo "No kubeconfig specified" >&2
	exit 1
fi

function check_cert_data() {
	[ "$(echo "$1" | cert_mod)" = "$(get_key_from_kubeconfig | key_mod)" ] 
}

function get_key_from_kubeconfig() {
	grep client-key-data: $TGT_KUBECONFIG | \
		sed 's/^\s\+client-key-data:\s*//' | \
		base64 -d
}

function cert_mod() {
	openssl x509 -modulus -noout
}

function key_mod() {
	openssl rsa -modulus -noout
}

function backup_file() {
	modtime=$(date -d @$(stat -c %Y $1) "+%Y%m%d%H%M")
	modhash=$(md5sum $1 | cut -d' ' -f1 | cut -c 1-8)
	bakfile=/root/$(basename $(dirname $1))_$(basename $1)_${modtime}_${modhash}

	cp -f $1 $bakfile
}

function replace_cert_in_kubeconfig() {
	sed -i 's/^\(\s\+client-certificate-data:\s*\)\(.*\)$/\1'"${1}"'/' $TGT_KUBECONFIG
}

function restart_services() {
	# kops runs kube-proxy as a pod, but hard to track down via containerd
	# so unga bugna, kubernetes will restart it
	pkill kube-proxy
	systemctl restart kubelet
}

if ! check_cert_data "$new_cert_pem"; then
	echo "Could not verify provided certificate data." >&2
	exit 1
fi

backup_file $TGT_KUBECONFIG

replace_cert_in_kubeconfig "$(echo "$new_cert_pem" | base64 -w0)"

restart_services

