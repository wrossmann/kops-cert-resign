#!/bin/bash -euo pipefail

if [ -z "$SSH_USER" ]; then
	SSH_USER=$(whoami)
fi

# allow functions to exit script
MYPID=$$
trap "exit 1" TERM

function info() {
	echo INFO "$@" >&2
}

function err() {
	echo ERROR: "$@" >&2
	kill -s TERM $MYPID
}

function s3_check_exist() {
	info Checking s3://${1}/${2} exists
	aws s3api get-object-attributes \
		--bucket $1 \
		--key $2 \
		--object-attributes Checksum &>/dev/null
}

function s3_get_file_securely() {
	# s3_get_file_securely misbehaves if the file does not exist, so we check first
	if ! s3_check_exist $1 ${2}; then
		err "File [${2}] not found in bucket [${1}]"
	fi

	info Getting s3://${1}/${2} securely
	# do not write sensitive files to disk temporarily
	pipe=$(mktemp -up ./)
	exec 63<>$pipe
	rm $pipe
	aws s3api get-object \
		--bucket $1 \
		--key $2 \
		/proc/self/fd/63 \
		>/dev/null && \
	cat /proc/self/fd/63
}

function get_ca_data() {
	tgt_file=${2}/pki/private/kubernetes-ca/keyset.yaml
	s3_get_file_securely $1 ${tgt_file}
}

function get_ca_public() {
	yq -r '.spec.keys[0].publicMaterial' $1 | base64 -d
}

function get_ca_private() {
	yq -r '.spec.keys[0].privateMaterial' $1 | base64 -d
}

function get_host_csr() {
	info Getting ${3} CSR from $1
	(
		echo "TGT_KUBECONFIG=\"${2}\""
		cat kube_get_csr.sh
	) | ssh ${SSH_USER}@${1} sudo bash -s
}

function sign_certificate() {
	info Signing new certificate
	# ensure that the index file exists
	if [ ! -f ./ca/index.txt ]; then
		touch ./ca/index.txt
	fi

	openssl ca \
		-batch \
		-config openssl-ca.cnf \
		-extensions v3_ext \
		-days $((465 + $RANDOM % 14)) \
		-cert $1 \
		-keyfile $2 \
		-in $3 \
		-out - | openssl x509 -out - -outform PEM
}

function set_host_certificate() {
	info Setting $3 cert on $1
	(
		echo "TGT_KUBECONFIG=\"${3}\""
		echo "new_cert_pem=\"${2}\""
		cat kube_set_cert.sh
	) | \
		ssh ${SSH_USER}@${1} sudo bash -s
}

bucket=$1
cluster_name=$2
tgt_hosts=${@:3}

ca_yaml=$(get_ca_data $bucket $cluster_name)

for tgt_host in $tgt_hosts; do
	#echo $bucket $cluster_name $tgt_host
	#continue
	for conf_path in /var/lib/kube-proxy/kubeconfig /var/lib/kubelet/kubeconfig; do
		info Generating new cert for $conf_path
	
		new_cert="$(sign_certificate <(get_ca_public <<<$ca_yaml) <(get_ca_private <<<$ca_yaml) <(get_host_csr $tgt_host $conf_path))"
	
		set_host_certificate $tgt_host "$new_cert" $conf_path
	done
	sleep 5
done
