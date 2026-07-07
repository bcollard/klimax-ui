# Klimax UI

> macOS companion app for the [klimax](https://github.com/bcollard/klimax) CLI. Visualize your VM, kind clusters, and registry mirrors — without leaving the menu bar.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

---

## Why

`klimax` runs a Lima-based macOS VM that hosts your kind clusters and registry mirrors. The CLI is great for one-off commands, but to keep an eye on **what's running, how loaded it is, and which LoadBalancer services are reachable**, you'd otherwise be juggling `klimax cluster list`, `kubectl get`, `kubectl top`, `ssh top`, and `du -sh ~/.klimax/registry-cache/*` in different terminals.

Klimax UI rolls all of that into one native SwiftUI app:

- **VM dashboard** — live CPU% and memory graphs, sampled every 5 s over the SSH ControlMaster socket klimax already maintains.
- **Per-cluster view** — node + pod inventory, helm-installable `metrics-server`, live CPU/memory time series, top pods by CPU and memory.
- **LoadBalancer service browser** — lists every `Service` with externalIPs, probes each `(ip, port)` over TCP, and renders a clickable link when reachable.
- **Registry mirror inspector** — cache disk usage and image count for each mirror in `~/.klimax/registry-cache/`.
- **Cluster creation, live** — create a cluster and watch its `kind` log stream in-app (with a cancel button); a "delete all" action tears the whole set down.
- **Labels & fleets** — shows each cluster's node labels (fleet, region/zone, …), badges its fleet, and can add a label to a running cluster (`klimax cluster label`, needs klimax 0.1.35+).
- **kubectl context** — badges the active cluster and switches `current-context` from the cluster view.
- **Stays live** — auto-refreshes when the VM starts/stops or clusters are created/deleted out-of-band (e.g. via the CLI).
- **Single-VM model** — klimax only ever runs one VM, so the sidebar surfaces that one VM at the top and the rest of the workspace beneath it.

## Install

```bash
brew tap bcollard/klimax
brew install --cask klimax-ui
```

Or grab the latest `KlimaxUI.dmg` (or `.zip`) from the [Releases](https://github.com/bcollard/klimax-ui/releases) page.

Requirements:

- macOS 14 Sonoma or later
- A working [klimax](https://github.com/bcollard/klimax) install — at least one VM under `~/.klimax/`
- `kubectl` and `helm` on PATH (used for cluster operations; klimax pulls these in)

The release build is signed with a Developer ID and notarized by Apple, so Gatekeeper opens it without warnings.

## How it works

No backend, no daemon, no new state — Klimax UI reads from the same places klimax itself uses:

```
┌─────────────────────────┐    ┌──────────────────────┐    ┌──────────────────────┐
│ ~/.klimax/<vm>/         │    │ kind clusters        │    │ ~/.klimax/           │
│   lima.yaml, ssh.config │    │   (kubeconfig)       │    │   registry-cache/    │
│   vz.pid (liveness)     │    │                      │    │                      │
└──────────┬──────────────┘    └──────────┬───────────┘    └──────────┬───────────┘
           │                              │                           │
           ▼                              ▼                           ▼
  InstanceDiscovery /        KubeClient (kubectl shell-out)     RegistryCacheInspector
  GuestSSH (ssh -F)          MetricsClient (kubectl raw)        + DirectorySize (du -sk)
           │                              │                           │
           └──────────────┬───────────────┴───────────────────────────┘
                          ▼
                       AppModel
                          │
                          ▼
                       SwiftUI
```

- **VM stats** come straight from `/proc/stat` and `/proc/meminfo` inside the guest, read over SSH every 5 s. CPU% is computed as `1 − idleΔ/totalΔ` (idle includes iowait).
- **Cluster metrics** come from the Kubernetes `metrics.k8s.io` API. If `metrics-server` isn't installed yet, the Metrics tab offers a one-click Helm install with `--set args[0]=--kubelet-insecure-tls` (required for kind's self-signed kubelet).
- **LoadBalancer reachability** is probed via `NWConnection` from the host — actual TCP, not a static CIDR check.
- **Cache size** uses `du -sk`; image count walks the Docker registry v2 layout (`_manifests/tags/*/current/link` for tags, `_manifests` dirs for repos).

See [`CLAUDE.md`](CLAUDE.md) for the full architecture notes (file-by-file map, polling cadences, why we shell out to `kubectl` rather than using a native Swift Kubernetes client).

## Build from source

```bash
git clone https://github.com/bcollard/klimax-ui
cd klimax-ui
./build.sh                                                    # → .build/bundler/apps/KlimaxUI/KlimaxUI.app (ad-hoc signed)
cp -R .build/bundler/apps/KlimaxUI/KlimaxUI.app /Applications/
open /Applications/KlimaxUI.app
```

Requires Xcode (for the Swift 6 toolchain) and [swift-bundler](https://github.com/moreSwift/swift-bundler).

### Cutting a release

```bash
# Bump `version` in Bundler.toml first.
./scripts/release.sh
# → .build/bundler/apps/KlimaxUI/KlimaxUI.{zip,dmg}
# → both signed with Developer ID, notarized, stapled, Gatekeeper-verified
# → prints a ready-to-paste cask block for bcollard/homebrew-klimax
```

The script requires:

- Developer ID Application cert in the login keychain.
- A `notarytool` keychain profile (default `klimax-notary`):

  ```bash
  xcrun notarytool store-credentials klimax-notary \
    --apple-id you@example.com --team-id YOURTEAMID \
    --password <app-specific-password>
  ```

- `brew install create-dmg` for the DMG step.

Then upload the produced `KlimaxUI.dmg` and `KlimaxUI.zip` to a new GitHub release, and paste the cask block into `Casks/klimax-ui.rb` in the [`bcollard/homebrew-klimax`](https://github.com/bcollard/homebrew-klimax) tap.

## Related

- [klimax](https://github.com/bcollard/klimax) — the Go CLI this app companions.
- [swift-bundler](https://github.com/moreSwift/swift-bundler) — turns SwiftPM executable packages into proper macOS app bundles.
