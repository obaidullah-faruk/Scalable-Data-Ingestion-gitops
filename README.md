# Scalable-Data-Ingestion-gitops

Desired state for the Kubernetes cluster that runs [Scalable-Data-Ingestion](https://github.com/obaidullah-faruk/Scalable-data-ingestion), and the code that builds its nodes.

## Layout

| Path | Contents |
|---|---|
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

4. Add the nodes to your SSH config, for example in `~/.ssh/config.d/homelab` with `Include ~/.ssh/config.d/*` as the first line of `~/.ssh/config`:
   ```
   Host cp-1 worker-1 worker-2
     User ops
     IdentityFile ~/.ssh/homelab_ed25519
     IdentitiesOnly yes
   ```

5. Check that Ansible reaches every node. Run Ansible from `infra/ansible/`, where it picks up `ansible.cfg` and the inventory:
   ```bash
   cd infra/ansible
   ansible all -m ping --become
   ```

6. Prepare the nodes for kubeadm: OS settings, containerd, and kubelet, kubeadm and kubectl at the version pinned in `inventory/group_vars/all.yml`:
   ```bash
   ansible-playbook site.yml
   ```
   Run it on all nodes, without `--limit`: every node's `/etc/hosts` is built from the facts of all nodes. A rerun changes nothing.

## Operations

Run from `infra/ansible/`.

| Task | Command |
|---|---|
| Upgrade OS packages, one node at a time, rebooting when needed | `ansible-playbook upgrade-os.yml` |
| Lint the playbooks | `ansible-lint` |

Kubernetes packages are held, so OS upgrades skip them. The collections the playbooks use are listed in `requirements.yml`.

`infra/vms/destroy-vms.sh` deletes the VMs and all their data.

## Access

```bash
ssh cp-1
```

Nodes accept SSH as `ops` with the lab key only. Password login is disabled. `ops` has passwordless sudo.
