#!/usr/bin/env bash
# Issues a client certificate through the Kubernetes CSR API and writes a kubeconfig that uses it.
# The certificate's CN is the user name and its O is the group, which RBAC binds to roles.
# Run with an admin kubeconfig.
#
#   infra/access/issue-user-cert.sh <user> <group> [days]
#
# The kubeconfig is written to ~/.kube/<user>.conf, or to $OUT_DIR. Rerun before it expires.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <user> <group> [days]" >&2
  exit 1
fi

user="$1"
group="$2"
days="${3:-30}"
kubeconfig="${OUT_DIR:-$HOME/.kube}/$user.conf"
csr_name="$user-$(date +%Y%m%d%H%M%S)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The private key never leaves this machine. Only the request goes to the cluster.
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$work/key.pem" 2>/dev/null
openssl req -new -key "$work/key.pem" -subj "/CN=$user/O=$group" -out "$work/request.csr"

kubectl apply -f - <<YAML
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $csr_name
spec:
  request: $(base64 < "$work/request.csr" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: $((days * 86400))
  usages:
    - client auth
YAML
kubectl certificate approve "$csr_name"

for _ in $(seq 1 30); do
  certificate="$(kubectl get csr "$csr_name" -o jsonpath='{.status.certificate}')"
  [[ -n "$certificate" ]] && break
  sleep 1
done
if [[ -z "$certificate" ]]; then
  echo "the certificate for $csr_name was not issued" >&2
  exit 1
fi
base64 -d <<<"$certificate" > "$work/cert.pem"
kubectl delete csr "$csr_name" >/dev/null

server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > "$work/ca.crt"

rm -f "$kubeconfig"
(
  umask 077
  export KUBECONFIG="$kubeconfig"
  kubectl config set-cluster homelab --server="$server" --certificate-authority="$work/ca.crt" --embed-certs >/dev/null
  kubectl config set-credentials "$user" --client-certificate="$work/cert.pem" --client-key="$work/key.pem" --embed-certs >/dev/null
  kubectl config set-context "$user@homelab" --cluster=homelab --user="$user" >/dev/null
  kubectl config use-context "$user@homelab" >/dev/null
)

echo "Wrote $kubeconfig for $user in group $group, valid until $(openssl x509 -enddate -noout -in "$work/cert.pem" | cut -d= -f2)"
