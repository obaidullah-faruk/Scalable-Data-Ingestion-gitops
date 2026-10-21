# Scalable-Data-Ingestion-gitops

Desired state for the Kubernetes cluster that runs [Scalable-Data-Ingestion](https://github.com/obaidullah-faruk/Scalable-data-ingestion), and the code that builds its nodes.

## Layout

| Path | Contents |
|---|---|
| `infra/vms/` | cloud-init for the cluster VMs |

`infra/` is run from an operator machine. ArgoCD never syncs it.

## Nodes

Ubuntu arm64 VMs on Multipass.

| Node | Role |
|---|---|
| cp-1 | control plane |
| worker-1 | stateful workloads |
| worker-2 | stateless workloads |

## Prerequisites

- macOS on Apple Silicon
- Multipass, Ansible, kubectl and Helm:
  ```bash
  brew install --cask multipass
  brew install ansible kubectl helm
  ```

## Setup

1. Create the SSH key the nodes will trust:
   ```bash
   ssh-keygen -t ed25519 -C homelab-k8s -f ~/.ssh/homelab_ed25519
   ```
   Its public key is added to each node at creation.

## Access

Nodes accept SSH as `ops` with the lab key only. Password login is disabled. `ops` has passwordless sudo.
