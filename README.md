# Scalable-Data-Ingestion-gitops

Desired state for the Kubernetes cluster that runs [Scalable-Data-Ingestion](https://github.com/obaidullah-faruk/Scalable-data-ingestion), and the code that builds its nodes.

## Layout

| Path | Contents |
|---|---|
| `bootstrap/` | The root Application and the list of everything it syncs |
| `projects/` | ArgoCD AppProjects |
| `platform/` | Cluster add-ons, namespaces and shared services, one folder each |
| `apps/` | The app: a Kustomize base and one overlay per environment |
| `infra/vms/` | Scripts and cloud-init that create the cluster VMs |
| `infra/ansible/` | Inventory and playbooks that configure the nodes |

`infra/` is run from an operator machine. ArgoCD never syncs it.

## Nodes

Ubuntu 24.04 arm64 VMs on Multipass. Sizes are set in `infra/vms/create-vms.sh`.

| Node | Role |
|---|---|
| cp-1 | control plane |
| worker-1 | stateful workloads |
| worker-2 | stateless workloads |

## Prerequisites

- macOS on Apple Silicon
- Multipass, Ansible, ansible-lint, kubectl and Helm:
  ```bash
  brew install --cask multipass
  brew install ansible ansible-lint kubectl helm
  ```

## Setup

1. Create the SSH key the nodes will trust:
   ```bash
   ssh-keygen -t ed25519 -C homelab-k8s -f ~/.ssh/homelab_ed25519
   ```
   Its public key is added to each node at creation.

2. Create the VMs:
   ```bash
   infra/vms/create-vms.sh
   ```
   Set `SSH_PUBLIC_KEY_FILE` to use a different key. Existing VMs are skipped, so the script is safe to rerun.

3. Add the nodes to `/etc/hosts`, using the IPs from `multipass list`:
   ```
   <cp-1 IP>      cp-1 k8s-api.lab
   <worker-1 IP>  worker-1
   <worker-2 IP>  worker-2
   ```
   IPs stay the same across restarts. Recreated VMs get new IPs and new SSH host keys: update `/etc/hosts` and remove the old keys with `ssh-keygen -R <name>`.

4. Add the nodes to your SSH config, for example in `~/.ssh/config.d/homelab` with `Include ~/.ssh/config.d/*` as the first line of `~/.ssh/config`:
   ```
   Host cp-1 worker-1 worker-2
     User ops
     IdentityFile ~/.ssh/homelab_ed25519
     IdentitiesOnly yes
   ```

5. Install the Ansible collections and check that Ansible reaches every node. Run Ansible from `infra/ansible/`, where it picks up `ansible.cfg` and the inventory:
   ```bash
   cd infra/ansible
   ansible-galaxy collection install -r requirements.yml
   ansible all -m ping --become
   ```

6. Build the cluster:
   ```bash
   ansible-playbook site.yml
   ```
   The playbook:
   - prepares every node: OS settings, containerd, and kubelet, kubeadm and kubectl at the version pinned in `inventory/group_vars/all.yml`
   - runs `kubeadm init` on cp-1, installs Calico and joins the workers with their labels and taints from `inventory/hosts.yml`
   - approves each kubelet's serving certificate
   - copies the admin kubeconfig to `~/.kube/homelab-admin.conf` on this machine
   - installs ArgoCD with the values in `platform/argocd/values.yaml` and applies the root Application, `bootstrap/root.yaml`

   `kubeadm init` and `join` run only on nodes that aren't part of the cluster yet. Run the playbook on all nodes, without `--limit`: every node's `/etc/hosts` is built from the facts of all nodes. A rerun changes nothing.

## Operations

Run from `infra/ansible/`.

| Task | Command |
|---|---|
| Upgrade OS packages, one node at a time, rebooting when needed | `ansible-playbook upgrade-os.yml` |
| Apply a change to `platform/argocd/values.yaml` | `ansible-playbook site.yml` |
| Lint the playbooks | `ansible-lint` |

Kubernetes packages are held, so OS upgrades skip them. The collections the playbooks use are listed in `requirements.yml`.

`infra/vms/destroy-vms.sh` deletes the VMs and all their data.

### Resize a node

Multipass changes CPUs and memory only on a stopped VM. Do one node at a time, and update `infra/vms/create-vms.sh` to match:

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data   # workers only
multipass stop <node>
multipass set local.<node>.memory=5G
multipass set local.<node>.cpus=3
multipass start <node>
kubectl uncordon <node>
```

Pods on worker-1 can't move to another node, so the data services are down until it's back. The IP stays the same.

## Access

### SSH

```bash
ssh cp-1
```

Nodes accept SSH as `ops` with the lab key only. Password login is disabled. `ops` has passwordless sudo.

### kubectl

People use their own client certificate, issued through the Kubernetes CSR API. The certificate's CN is the user name and its O is the group:

```bash
export KUBECONFIG=~/.kube/homelab-admin.conf
infra/access/issue-user-cert.sh <user> <group> [days]   # default 30 days
```

The script writes `~/.kube/<user>.conf`. The private key stays on the machine that ran it. Rerun the script before the certificate expires.

| Group | Cluster | ingestion-dev | ingestion-prod | object-storage |
|---|---|---|---|---|
| `platform-admins` | `cluster-admin` | all | all | all |
| `ingestion-devs` | view nodes | `edit` | `view` | `view` |
| `viewers` | view nodes | `view` | `view` | `view` |

The bindings are in `platform/access/`. Built-in `view` can't read Secrets; `edit` can.

A certificate can't be revoked before it expires. To cut someone off early, remove their group's binding, or issue certificates with a short expiry.

The playbook's admin kubeconfig, `~/.kube/homelab-admin.conf`, is for emergencies, for example when RBAC is broken. Its user is in `kubeadm:cluster-admins`.

### ArgoCD UI

The UI is served at `http://argocd.lab` through the cluster Gateway, whose address is set in `platform/envoy-gateway/config/gateway.yaml`. Add the name to `/etc/hosts`:

```
192.168.252.240  argocd.lab
```

Log in as `admin`.

### The app

Prod is served at `http://ingest.lab` and dev at `http://dev.ingest.lab`. Browsers upload files to S3 at `http://s3.ingest.lab`. Add the names to `/etc/hosts`:

```
192.168.252.240  dev.ingest.lab s3.ingest.lab ingest.lab
```

## Secrets

Secrets are stored in Git as SealedSecrets. Only the Sealed Secrets controller in the cluster can decrypt them, and each one only in the namespace it was sealed for.

To seal a secret, pipe it from kubectl to `kubeseal` so the plain value is never written to disk:

```bash
kubectl create secret generic <name> -n <namespace> \
  --from-literal=<key>=<value> --dry-run=client -o yaml \
  | kubeseal --controller-namespace sealed-secrets --format yaml \
  > apps/ingestion/overlays/<env>/secrets/<name>.yaml
```

### Controller key backup

A new cluster can only decrypt the secrets in this repo with the controller's private keys. The controller adds a new key every 30 days and keeps the old ones. Back them up after each new key, and store the file outside Git:

```bash
kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > sealed-secrets-keys.yaml
```

To restore, apply the file before the controller starts, or apply it and then restart the controller:

```bash
kubectl apply -f sealed-secrets-keys.yaml
kubectl -n sealed-secrets rollout restart deployment sealed-secrets-controller
```
