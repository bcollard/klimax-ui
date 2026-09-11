# Klimax UI — Architecture Notes

A native macOS app that reads klimax state directly (no CLI shell-out for state), talks to the guest VM over the SSH ControlMaster socket klimax already maintains, and uses `kubectl`/`helm` shell-outs for cluster operations.

- **Bundle id:** `dev.bcollard.KlimaxUI`
- **Display name:** Klimax
- **Target:** macOS 14+
- **Toolchain:** Swift 6, SwiftPM executable target
- **Distribution:** Developer-ID-signed + notarized DMG via the [`bcollard/homebrew-klimax`](https://github.com/bcollard/homebrew-klimax) tap. Built with [swift-bundler](https://github.com/moreSwift/swift-bundler) (config in `Bundler.toml`).

---

## Quick start

```bash
./build.sh                                                # → .build/bundler/apps/KlimaxUI/KlimaxUI.app (ad-hoc signed)
cp -R .build/bundler/apps/KlimaxUI/KlimaxUI.app /Applications/
open /Applications/KlimaxUI.app
```

For a signed + notarized release, use `./scripts/release.sh` (see [Release](#build-and-release)).

---

## Project layout

```
klimax-ui/
├── Package.swift                       # SwiftPM, macOS 14, executable target, Yams dep
├── Bundler.toml                        # swift-bundler config; source of truth for Info.plist
├── build.sh                            # dev path: swift-bundler bundle + ad-hoc sign
├── scripts/release.sh                  # full Developer ID release flow
├── Sources/KlimaxUI/
│   ├── KlimaxUIApp.swift               # @main, WindowGroup, NSApp activationPolicy hack
│   ├── AppAssets.swift                 # loads klimax-logo.png from Bundle.module
│   ├── AppModel.swift                  # @MainActor @Observable, all state + polling tasks
│   ├── Models/
│   │   ├── Instance.swift              # VM struct: name, dir, runtime, ssh, lima config
│   │   ├── Cluster.swift               # KindCluster: name, num, apiPort, kubeconfigPath
│   │   ├── KlimaxConfig.swift          # mirrors ~/.klimax/_config/config.yaml
│   │   ├── KubeTypes.swift             # KubeNode/Pod/Deployment/Service decodables
│   │   ├── Metrics.swift               # cluster metric samples + ring-buffer history
│   │   ├── VMMetrics.swift             # VM sample + history (raw /proc/stat ticks for CPU%)
│   │   ├── AppSettings.swift           # @Observable prefs (visibility + poll cadences), UserDefaults-backed
│   │   ├── LogRecord.swift             # LogScope enum + LogRecord for scoped action logs
│   │   ├── DoctorReport.swift          # decodes `klimax doctor -o json` (stable check ids)
│   │   ├── KlimaxStatus.swift         # decodes `klimax status -o json` — VM host mounts
│   │   ├── DockerContainer.swift       # guest container, compose membership, classification
│   │   └── SidebarSelection.swift      # enum: .cluster(name) | .mirror(name) | .container(id) | nil
│   ├── Services/
│   │   ├── InstanceDiscovery.swift     # scans ~/.klimax/, reads vz.pid liveness, lima.yaml
│   │   ├── SSHConfigParser.swift       # hand-parses OpenSSH config from ssh.config
│   │   ├── GuestSSH.swift              # ssh -F shell-out; reads /proc/stat, /proc/meminfo
│   │   ├── ProcessRunner.swift         # async Process wrapper with PATH search
│   │   ├── KlimaxCLI.swift             # wraps `klimax cluster list/status/doctor -o json`, up/down, create/delete
│   │   ├── KubeClient.swift            # kubectl shell-out: nodes/pods/services/deployments
│   │   ├── Helm.swift                  # helm repo add/update/install metrics-server
│   │   ├── DockerClient.swift          # guest `docker ps`(+inspect labels)/logs/lifecycle over GuestSSH
│   │   ├── CodeSignatureCheck.swift    # codesign + spctl + stapler on the running .app bundle
│   │   ├── MetricsClient.swift         # kubectl get --raw /apis/metrics.k8s.io/v1beta1/{nodes,pods}
│   │   ├── QuantityParser.swift        # k8s quantity strings → millicores / MiB
│   │   ├── TCPProbe.swift              # NWConnection probe with 1.5s timeout
│   │   ├── DirectorySize.swift         # du -sk wrapper
│   │   └── RegistryCacheInspector.swift # counts tags + repos in Docker registry v2 layout
│   ├── Views/
│   │   ├── RootView.swift              # NavigationSplitView dispatcher
│   │   ├── SidebarView.swift           # VM card + clusters + mirrors + containers sections
│   │   ├── OverviewDetailView.swift    # home dashboard with cluster/mirror/container cards + VM charts
│   │   ├── ClusterDetailView.swift     # Info / Services / Metrics tab picker
│   │   ├── ServicesTabView.swift       # LoadBalancer services with per-port TCP probes
│   │   ├── MirrorDetailView.swift      # mirror config + cache storage + usage hint
│   │   ├── MetricsChartsView.swift     # cluster CPU/mem charts + top pods table
│   │   ├── VMChartsView.swift          # VM CPU%/mem charts (Swift Charts + hover tooltips)
│   │   ├── SettingsView.swift          # ⌘, preferences window: Visibility/Refresh/Diagnostics/About
│   │   ├── DiagnosticsTabView.swift    # klimax doctor checks + app integrity block
│   │   ├── ContainerDetailView.swift   # user's container: compose stack, ports, labels, logs, lifecycle
│   │   ├── ConsoleLogView.swift        # collapsible aggregated console panel (bottom of detail)
│   │   ├── LogConsoleView.swift        # scrollable colorized log box (per-view "Last action" cards)
│   │   └── NewClusterSheet.swift       # modal for `klimax cluster create`
│   └── Resources/
│       └── klimax-logo.png             # used both for in-app branding and AppIcon (via swift-bundler)
└── .gitignore
```

---

## Data sources

We **bypass the klimax CLI for state-reads** wherever possible — every CLI invocation is a fork+exec and stale state from the CLI's own caching path would only confuse the UI. State of record:

### `~/.klimax/<vm>/` — VM truth

- `lima.yaml` — Lima config; we read `cpus`, `memory`, `disk` for the VM card.
- `ssh.config` — generated by klimax; gives us host/port/user/IdentityFile/ControlPath.
- `vz.pid` — VM process ID; `kill(0, pid)` tells us if the VM is running.
- `_config/config.yaml` — klimax-level config (mirrors, kind defaults). Decoded via Yams.

`InstanceDiscovery.scan()` walks this directory, skips reserved entries (`_config`, `registry-cache`, `share`), and builds an `Instance`. Only one VM is ever expected.

### Guest VM — `/proc/stat` over SSH

`GuestSSH` shell-outs to `ssh -F <ssh.config> <host>`, riding the ControlMaster socket klimax already keeps open (no fresh handshake on each call). For the VM polling loop we issue a single SSH command that emits `/proc/stat | head -1` and `/proc/meminfo | head -3` separated by `---`, then parse:

- **CPU%** — `1 − idleΔ/totalΔ`, where `idle` is `(idle + iowait)` ticks. Requires a stored previous sample (`GuestRawSample`) to take the delta.
- **Memory** — `MemTotal − MemAvailable` for used, `MemTotal` for total.

Poll cadence: user-configurable, default 5 s (`AppSettings.vmPollSeconds`; read live off `settings.vmPollInterval` at the top of each loop). Skipped entirely when the "VM stats & graphs" preference is off.

### Kubernetes — `kubectl` shell-out

We shell to `kubectl --kubeconfig <path>` rather than embedding a Swift Kubernetes client because:

1. kubeconfig schemas (exec credential plugins, OIDC, etc.) drift constantly; reusing `kubectl` inherits Apple's bug-fix budget.
2. The user already has `kubectl` configured for these clusters.
3. The query surface we need is tiny (`get nodes/pods/services/deployments -o json`).

`KubeClient` wraps the common verbs. `MetricsClient` hits `kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes` and `/pods` and decodes the result via private `NodeMetricsList` / `PodMetricsList` types. `QuantityParser` handles the menagerie of k8s quantity formats:

- `93642001n` → 93.6 millicores
- `123m` → 123 millicores
- `1.5Gi`, `512Mi`, `1024Ki` → MiB

Cluster metric poll cadence: user-configurable, default 15 s (`AppSettings.metricsPollSeconds`).

### LoadBalancer reachability — `NWConnection`

`TCPProbe.probe(host:port:)` opens a Network framework TCP connection with a 1.5 s timeout and treats `.waiting` as failure (so unreachable IPs fast-fail instead of stalling on retry). `OnceFlag` guards the `CheckedContinuation` against double-resume in the cancellation path.

For each selected cluster's LoadBalancer services, `AppModel.probeLoadBalancers(for:)` runs a `TaskGroup` over every `(externalIP, port)` and writes results to `serviceProbes[clusterName]`. The Services tab renders a green/red/spinner dot per port, and turns the row into a clickable `Link` when reachable.

### Registry mirror cache — filesystem inspection

`RegistryCacheInspector` walks each mirror directory under `~/.klimax/registry-cache/<mirror>/`:

- Total disk usage via `du -sk` (`DirectorySize`).
- Tag count via `find <path> -path '*/_manifests/tags/*/current/link' -type f`.
- Repository count via `find <path> -type d -name _manifests`.

This is exactly the Docker registry v2 on-disk layout — no registry HTTP API call needed.

### Guest containers — `docker ps` over SSH

`DockerClient` runs one guest command per refresh, in two sections separated by a
sentinel, and parses it into `DockerContainer`:

1. `docker ps -a --no-trunc --format …` — **tab**-separated, because `.Ports`,
   `.Networks`, `.Mounts` and `.Labels` are themselves comma-joined.
2. `docker ps -aq | xargs -r docker inspect --format '{{.Id}}\t{{json .Config.Labels}}\t{{json .Mounts}}'`
   — the label map and the typed mount list as JSON. Mounts come from here because the
   `{{.Mounts}}` ps column flattens binds and volumes into one undifferentiated list with
   no destination and no read-only flag.

Both ride the same SSH round-trip; the network hop is the cost, not the second local
docker call.

**Never parse `{{.Labels}}` for anything that drives behavior.** That column comma-joins
the label map *without escaping commas inside values*, and two labels routinely contain
them — `com.docker.compose.project.config_files` (one entry per `-f` flag) and
`com.docker.compose.depends_on`. A two-file compose stack silently splits into a bogus
entry and a truncated path. So:

- Every label the app **reasons about** gets its own `{{.Label "…"}}` column, which is
  structurally immune.
- The **displayed** label map comes from the `docker inspect` JSON, which is exact.
- The `{{.Labels}}` parse survives only as the fallback if the inspect pass fails —
  classification never depends on it, so a failure there can't make kind nodes show up
  as strays.

Classification (`DockerContainer.managed(mirrorNames:)`) decides what klimax owns:

- **kind nodes** by the `io.x-k8s.kind.cluster` label — the same signal `kind get
  clusters` uses, so it beats matching on the container name.
- **registry mirrors** by name against `registries.mirrors[].name` from the klimax
  config. klimax puts **no label** on these containers, so the config is the primary
  signal; a `registry-*` name on a `registry:<tag>` image is the fallback for a config
  that has drifted from what is actually running.

Everything else is the user's own and surfaces as **Docker containers** in the sidebar/overview/detail views when
`AppSettings.showContainers` is on. When it's off nothing queries the guest's docker at
all. Published ports are linked at the VM's **lima0** address, not `127.0.0.1`: klimax
sets `network.disablePortMirroring`, so Lima's loopback mirroring is off and lima0 is
the only address that works from the host.

#### Compose stacks

Docker containers are bucketed by `com.docker.compose.project` into
`AppModel.containerGroups` — stacks first (alphabetically, members ordered by service
then replica), standalone containers last. A stack is a unit the user thinks about as a
whole, so five flat `myapp-worker-{1..5}` rows next to an unrelated container hide the
one fact that matters about them. Inside a stack, rows and cards are titled by
**service** (`web`, `worker #2`), because the container name is just
`<project>-<service>-<n>` repeated.

Compose labels read (all verified against a live stack, Compose v5.5.1):

| Label | Use |
|---|---|
| `com.docker.compose.project` | the group key; stack name (launch dir unless `-p` / `COMPOSE_PROJECT_NAME`) |
| `com.docker.compose.service` | row/card title |
| `com.docker.compose.container-number` | replica index, 1-based; shown as `#n` only when > 1 |
| `com.docker.compose.oneoff` | `True`/`False` (Go casing, not JSON) — flags `docker compose run` throwaways |
| `com.docker.compose.project.working_dir` | shown on the group header and detail card |
| `com.docker.compose.project.config_files` | comma-separated list of compose files |

> ⚠️ **Never run `docker compose up` inside the klimax VM casually.** The Compose in the
> guest removes orphan containers *without* `--remove-orphans` being passed, and it
> considers kind node containers orphans — a `docker compose up` in a scratch project
> destroyed a running kind cluster's node (verified in `docker events`). Test compose
> label handling with `docker run -l com.docker.compose.project=…` instead, which
> produces identical labels with no orphan sweep.

`ContainerDetailView` offers start / stop / restart (logged under `LogScope.container(id)`)
and an on-demand `docker logs --tail N`. Deliberately **no `docker rm`** — removal is
unrecoverable and these containers aren't klimax's to destroy.

### Host mounts — `klimax status -o json`

klimax 0.1.59 added `vm.mounts`: host directories shared into the guest over virtiofs.
This matters more than it sounds, and it is the one place the UI can tell the user
something neither `docker` nor `kubectl` will:

> Docker runs **inside** the VM and resolves a bind-mount source **there**. Binding a host
> path klimax doesn't share does **not** fail — dockerd creates the missing directory in
> the guest and the container sees an empty one. The container starts, reports healthy,
> and silently has none of your files.

`KlimaxCLI.status()` decodes `klimax status -o json` for `mounts.shares` and
`mounts.pendingRestart`. Deliberately this and not `config.yaml`: klimax reads the share
list from the **Lima instance config**, so it answers "what does the VM actually have"
rather than "what will it have after the next restart" — and `pendingRestart` is klimax
telling us the two disagree. It costs one CLI invocation (~350 ms), so it rides
`refreshAll()` and never a poll loop. `mounts` is absent on older klimax; the optional
decodes to nil and the UI omits the section rather than guessing.

The overview titles this section **Volume mounts** and lists klimax's own registry-cache
share last and greyed out: it is a real share — a bind into it does reach the Mac, so it
stays in the data the backing check uses — but it is plumbing the user never configured,
so the count above it only counts theirs.

`AppModel.backing(for:)` resolves each container bind against that list —
`.hostShare` / `.guestOnly` / `.notApplicable` (a volume) / `.unknown` (klimax too old to
say, so we must not claim either way). The prefix test appends a `/` before comparing, so
a share of `/Users/me/projects` does not falsely claim `/Users/me/projectsX`. The
comparison is against `guestPath`, not `hostPath`, because a remapped `mountPoint` is what
docker actually resolves against.

The container detail view renders that per mount: green "on your Mac", orange "not shared
from your Mac — this path exists only inside the VM", nothing for a volume.

### Diagnostics — `klimax doctor` and the app's own signature

The Settings window's **Diagnostics** tab answers two unrelated questions.

`KlimaxCLI.doctor(fix:)` shells `klimax doctor -o json`; the check `id`s are a documented
stable contract on the klimax side, so `DoctorCheck.title` keys its labels off them and an
unknown `status` decodes to `.unknown` rather than failing the whole report. Nothing here
is polled — the probes (route table, in-guest iptables, Rosetta) are far too heavy for a
loop. `--fix` repairs the route / iptables / IP-forwarding checks itself, but the route fix
shells to `sudo`; launched from an app bundle there is no controlling terminal, so sudo
fails fast with "no tty present" and the UI surfaces that plus a copyable command.

The tab's **Network & trust** section reads `network.proxy` and `vm.caCerts` from the
klimax config (0.1.60+). Both are invisible everywhere else and both fail in ways that
look like something else — a proxy-less pull hangs, an untrusted CA fails with "certificate
signed by unknown authority". An **absent** proxy block is not "no proxy": klimax inherits
macOS's system settings, so the UI says "inherited from macOS" rather than "none".

`CodeSignatureCheck` verifies the *running* bundle with `codesign --verify`, `codesign
-dvvv` (the `-dvvv` is what makes it print the `Authority=` chain at all), `spctl -a -vv`,
and `xcrun stapler validate`. Notarization is decided by the **stapled ticket** or a
`source=Notarized Developer ID` from spctl — never by spctl's bare "accepted", which means
nothing on a Mac with assessment disabled (`override=security disabled`, surfaced as a
caveat). A `./build.sh` bundle reports "ad-hoc (local build)", which is a distinct state
from a broken signature. This is not build provenance: it says nothing about which commit
produced the binary.

---

## App model and polling

`AppModel` is a `@MainActor @Observable` class holding every piece of state the views read. It is constructed with an `AppSettings` (`AppModel(settings:)`) and reads the poll cadences off it on **each loop iteration**, so changing an interval in the Settings window takes effect on the next cycle without restarting any task. Polling is structured around four tasks held as properties:

- `vmPollTask` — `settings.vmPollInterval` loop (default 5 s) driving `collectVMSample()` (`GuestSSH.rawSample()` → CPU%/mem). Started by `startVMPollingIfRunning()` when the VM is up **and** the "VM stats & graphs" preference is on; toggling that preference (via a `RootView` `.onChange`) starts/stops it.
- `metricsTask` — `settings.metricsPollInterval` loop (default 15 s) scoped to the selected cluster; fetches node + pod metrics and appends to the per-cluster `MetricsHistory` ring buffer (capacity 60).
- `probeTask` — one-shot `TaskGroup` triggered on cluster selection or service refresh.
- `statePollTask` — `settings.clusterRefreshInterval` loop (default 6 s, `pollForExternalChanges()`) that detects out-of-band changes: VM started/stopped, clusters created/deleted via the CLI, and — when `showContainers` is on — containers that appeared or vanished (there is no cheaper signal for a `docker run` in a terminal than re-listing). On a change it calls `refreshAll()`/`refreshClusters()` so the UI stays live without a manual ⌘R. Skips while `inFlightAction`/a running `creation` would refresh anyway.

### Settings and scoped action logs

- **`AppSettings`** (`@MainActor @Observable`, `UserDefaults`-backed) holds visibility toggles (`showConsoleLog`, `showMirrors`, `showVMStats`, `showContainers`) and the three poll cadences. One instance is created in `KlimaxUIApp`, injected into the SwiftUI environment (`@Environment(AppSettings.self)`) for the views **and** passed to `AppModel` for the loops. The `Settings { SettingsView(model:) }` scene binds it to ⌘, and the standard "Settings…" menu item; the sidebar footer's "Settings & About" button opens the same window via `@Environment(\.openSettings)`. The window's fourth tab, **About**, is the home for version/environment facts — Klimax UI, klimax CLI, the Kubernetes version of the kind nodes, and the guest VM's distribution and kernel — so it takes `AppModel` as well as `AppSettings`.
- **Action logs are scoped** (`LogScope`: `.vm` / `.cluster(name)` / `.metrics(name)` / `.container(id)` / `.general`). Every completed action appends a `LogRecord` via `appendLog(scope:label:text:)`; each view surfaces only its relevant entry via `model.latestLog(for:)` / `latestLog(forAny:)` — the cluster Info/Services tabs show `.cluster`, the Metrics tab shows `.metrics`, the overview shows `.vm`/`.general`. The optional bottom **`ConsoleLogView`** (toggled by `showConsoleLog`, collapsible) shows the full timestamped `consoleTranscript` across all scopes.

`AppModel.refreshAll()` reloads VM state, clusters, mirrors, config, **and the klimax CLI version** (so it tracks CLI upgrades). `loadClusterDetail(_:)` fetches nodes/pods/services/deployments/version concurrently for the just-selected cluster.

### Cluster labels, fleet, and kube-context

- **Node labels aren't in `klimax cluster list`** — read them from `kubectl` node metadata (`KubeNode.metadata.labels`), cached per cluster in `AppModel.clusterLabels`. klimax applies `managed-by`, `klimax.dev/fleet`, `topology.kubernetes.io/{region,zone}`, `ingress-ready` (the last is set by the klimax CLI's kind config, not the UI). `AppModel.displayLabels(_:)` filters out k8s system labels.
- **Adding a label post-creation** uses `klimax cluster label <name> -l key=value` (KlimaxCLI.labelCluster) — **requires klimax 0.1.35+**.
- **kube-context names == cluster name** (klimax merges each cluster into `~/.kube/config` under a context named after the cluster, not `kind-<name>`), so `currentKubeContext == cluster.name` and `use-context <name>` both work directly.
- **The same node fetch also caches the kubelet version** (`AppModel.clusterNodeVersion`). `kubeNodeVersionSummary` reduces it for the About tab: one version when every cluster agrees, `mixed` (with a per-cluster tooltip) when they don't, and the configured `kind.nodeVersion` image tag from `config.yaml` as the fallback when no cluster is up.

The About tab also shows the guest VM's distribution and kernel (`GuestStats.osName` / `.kernel`), read in one SSH round-trip: `uname -r` plus `PRETTY_NAME` from `/etc/os-release`. They come from the full `stats()` call (refreshAll), not the 5 s sample loop, which just carries them forward.

The sidebar footer itself is down to two lines: the active kube context and the settings button. Note that `.textSelection(.enabled)` on a `Text` makes it draw in the label color and ignore `.foregroundStyle` — that's why those footer rows aren't selectable.

Selection state lives in `AppModel.selection: SidebarSelection?` and drives both the sidebar list selection and `RootView`'s detail dispatch.

---

## Key design decisions

### "Docker containers" are a separate concept from clusters

kind nodes and registry mirrors already have first-class places in the UI (the Clusters
and Registry mirrors sections). The Containers section is deliberately *everything else* —
what a `docker run` in a terminal left behind — so it never duplicates what's above it. It
is off by default: a stock klimax VM has none, and an empty section is worse than no
section.

### Single-VM model

klimax only ever runs one VM. The sidebar dedicates its top section to that one VM (logo, status, CPU/mem stats) and the rest of the workspace below. There is no VM list, no VM switcher — just `if let vm = model.vm` everywhere.

### Why we don't use the klimax CLI for state

`klimax cluster list -o json` is the one CLI command we DO use, because parsing kind's cluster discovery ourselves would duplicate klimax's work. For everything else (VM liveness, lima config, ssh config, mirror config) we read the filesystem directly. Reasons:

1. CLI invocation costs ~50–150 ms each (fork + Swift→klimax→Go→exit).
2. State files are the source of truth — the CLI just reads them.
3. UI polling cadences would multiply CLI invocations.

### Re-using klimax's SSH ControlMaster

When klimax brings the VM up, it opens an OpenSSH ControlMaster socket described by `~/.klimax/<vm>/ssh.config`. By passing `-F <ssh.config>` to our own `ssh` calls, we ride that existing socket — no fresh TCP handshake, no fresh auth, sub-100 ms round-trip for short commands.

### Hardened-runtime re-sign step

swift-bundler v3 does code-sign with the supplied Developer ID identity, but **does not** add the `--options runtime` flag — and notarization rejects bundles without the hardened runtime. `scripts/release.sh` therefore re-signs after the initial bundle with `--options runtime --timestamp`. Don't simplify this away.

### App lives outside the App Store

The app shells out to `ssh`, `kubectl`, `helm`, reads arbitrary paths under `~/.klimax/`, opens SSH ControlMaster sockets, and uses `NWConnection` to probe arbitrary LAN IPs. The App Store sandbox would fight every one of those. Homebrew cask via Developer ID is the right call here.

---

## Build and release

### Build (dev)

```bash
./build.sh                  # swift-bundler bundle -c release + ad-hoc codesign
                            # → .build/bundler/apps/KlimaxUI/KlimaxUI.app
```

### Release (signed + notarized + DMG + ZIP)

Prerequisites (one-time):

- Apple Developer ID Application certificate in the login keychain.
- A `notarytool` keychain profile:
  ```bash
  xcrun notarytool store-credentials klimax-notary \
    --apple-id you@example.com --team-id YOURTEAMID \
    --password <app-specific-password>
  ```
- `brew install create-dmg`.
- `swift-bundler` on PATH (`~/.local/bin/swift-bundler` built from [moreSwift/swift-bundler](https://github.com/moreSwift/swift-bundler)).

Bump `version` in `Bundler.toml`, then:

```bash
./scripts/release.sh
# → .build/bundler/apps/KlimaxUI/KlimaxUI.{zip,dmg}
# → both signed with Developer ID, notarized, stapled, Gatekeeper-verified
# → prints a ready-to-paste cask block (version + dmg sha256) at the end
```

Env overrides:

- `KLIMAX_SIGN_IDENTITY` — the Developer ID Application identity name.
- `KLIMAX_NOTARY_PROFILE` — the `notarytool` profile name (default `klimax-notary`).

### Publishing checklist

1. `./scripts/release.sh` — verify both artifacts land in `.build/bundler/apps/KlimaxUI/`.
2. `gh release create vX.Y.Z .build/bundler/apps/KlimaxUI/KlimaxUI.dmg .build/bundler/apps/KlimaxUI/KlimaxUI.zip --title "vX.Y.Z" --notes "..."`.
3. Paste the printed cask block into `Casks/klimax-ui.rb` in the [`bcollard/homebrew-klimax`](https://github.com/bcollard/homebrew-klimax) tap; commit and push.
4. End-users update via `brew upgrade --cask klimax-ui`.

---

## Known limitations

### metrics-server is a manual install

kind doesn't ship metrics-server out of the box. The Metrics tab detects this and offers a one-click Helm install:

```
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo update
helm install metrics-server metrics-server/metrics-server \
  -n kube-system --set args[0]=--kubelet-insecure-tls --wait --timeout 120s
```

The `--kubelet-insecure-tls` is required: kind's kubelet uses a self-signed cert that metrics-server otherwise rejects.

### CPU% requires a previous sample

The first VM sample after VM start shows no CPU% (we need a delta against a prior sample). After ~5 s the second sample arrives and the chart populates. This is normal; the empty state shows "Waiting for the first interval…".

### LoadBalancer probes assume routability

The probe runs from the macOS host. It assumes the LoadBalancer external IPs are routable from the host — usually true when klimax is set up with MetalL plus a host network bridge. If the user has split networking, the probe will report unreachable even though the IP works from elsewhere.

### App Store distribution would require sandboxing

The sandbox would block: `ssh` to arbitrary hosts, reading `~/.klimax/` without explicit Files-and-Folders entitlement, `NWConnection` to arbitrary LAN IPs, `kubectl`/`helm` shell-outs. Stick with the cask path.

---

## Future work

- **Logs view.** Tail `kubectl logs -f` for selected pods inside the app.
- **Resource graphs by namespace.** Top-N pods is useful; per-namespace stacked area would surface heavy tenants.
- **MetalLB IP allocation map.** Pull `MetalLB`'s `IPAddressPool` CRDs and show which ranges are in use vs free.
- **VM resize.** Edit `lima.yaml` (cpus/memory/disk) and trigger `klimax restart` from the UI.
- **Mirror prune.** Surface aged tags and offer a "delete tag" action via the registry HTTP API.
