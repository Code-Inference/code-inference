# OpenShell runtime (`--openshell`) — planned

> **Status: proposed, not implemented.** There is no `--openshell` flag in this
> repository yet. This document fixes the design agreed during review so that
> implementation starts from a stable reference instead of re-litigating the
> boundary. Reviewed against OpenShell 0.1.6 on 2026-10-29.

OpenShell is NVIDIA's runtime for autonomous agents. It is a second control
plane — a gateway plus a per-sandbox supervisor — not another launcher. This
document records how it would sit under `code-inference`, what it changes, and
what it deliberately does not do.

## 1. What OpenShell is

- **Gateway** (control plane): a container that holds policies, providers,
  sandbox records, and the credential store. It creates sandboxes through the
  Docker daemon, so it needs `/var/run/docker.sock`.
- **Supervisor** (data plane): a binary bind-mounted into every sandbox
  container. It owns the boundary.
- **Sandbox**: a Docker container created by the gateway from an OCI image.
  Its workload runs with `network=none`; every outbound connection is relayed
  through the supervisor.
- **Policy**: declarative YAML. Filesystem and process rules, plus
  `network_policies` keyed by the resolved path of the connecting binary, with
  L7 inspection for REST, GraphQL, MCP, WebSocket, JSON-RPC, and native TCP.
  Default is deny.
- **Providers**: credentials held by the gateway and injected only into
  requests bound for approved endpoints. The agent never sees the secret.
- **Workspaces**: an access and resource boundary. Sandboxes, providers,
  policies, and settings belong to a workspace and are not visible from
  another. Selected with `--workspace` or `OPENSHELL_WORKSPACE`.

OpenShell is Docker-native: the gateway runs as a container and each sandbox is
a container. The one thing it cannot do is let a container create the container
it is already running in, which is why the entrypoint cannot be the component
that creates the sandbox.

## 2. Why consider it, and what it is worth

What the integration would add that OpenShell does not provide:

- A local model: llama.cpp behind the `api` gateway, with PII masking,
  truncation, intent tags, and the existing response headers.
- Seven prebuilt agent images with git, gh, node, rust, python, playwright, and
  the shared bootstrap.
- Per-agent persistence (`--ephemeral`, `--ephemeral-keep-auth`, per-project
  volumes, external-disk backing).
- Project scaffolds, `--add-skills`, and guard scripts.
- Per-agent policy defaults that are known to work with local inference.

What OpenShell would add that we do not have:

- Kernel-level filesystem and process confinement inside the container.
- Default-deny, per-binary, L7-inspected egress.
- Credentials that the agent cannot read (HTTP providers only).
- Policy denials and structured audit events.

A thin wrapper over `openshell sandbox create` would not justify its
maintenance against a weekly-cadence 0.1.x dependency. The integration earns
its place only where OpenShell has no answer — inference, masking, tooling,
persistence, and policy defaults.

## 3. Division of responsibility

| Layer | Owner |
| --- | --- |
| Which agent, which volumes, which project | `code-inference` |
| Local inference and prompt masking | `code-inference` (`api` gateway) |
| Agent image contents and bootstrap | `code-inference` (`entrypoint.sh`) |
| Filesystem and network enforcement | OpenShell (supervisor policy) |
| Credential storage and injection | OpenShell (providers) |
| Sandbox lifecycle | OpenShell (gateway) |

`entrypoint.sh` remains the first process inside the sandbox, so bootstrap
still runs in our code, on every agent, from one shared script.

## 4. Constraints that shape the design

| Constraint | Consequence |
| --- | --- |
| The entrypoint cannot create its own sandbox | Something outside creates the sandbox; the entrypoint runs as its main command |
| Workload has `network=none`; supervisors use host or bridge mode | The sandbox cannot join the compose `internal` network; `api` is reached over the published host port |
| Loopback destinations are never authorized; private addresses need `allowed_ips` | `host.docker.internal:8000` with the Docker Desktop subnet, plus `tls: skip` for plain HTTP |
| Sandbox identity is non-root and the Docker driver has no privileged mode | `--privileged` and `--openshell` are mutually exclusive |
| Providers cover HTTP endpoints only | SSH stays as the git transport; credentials reach the sandbox by agent forwarding or a mounted key |
| A sandbox's workspace is the image `WORKDIR`; a mount cannot replace it | The project mounts at a subdirectory and the entrypoint `cd`s there |
| Volume admission labels are set at creation only | Admission must be resolved and created up front, not applied later |
| Bind mounts require `enable_bind_mounts` and disabled resource admission | Bind mounts are rejected as a workspace strategy: they bypass the isolation being adopted |

## 5. Flag contract

`--openshell` selects the runtime. It is parsed by `start.sh` and dispatched
through one internal helper; there is no per-agent `launch-openshell.sh` and no
second copy of the agent table.

| Form | Result |
| --- | --- |
| `--openshell --agent NAME` | Allowed |
| `--openshell --template NAME` | Allowed; bootstrap runs first |
| `--openshell --add-skills` | Allowed; installs into the project on the host |
| `--openshell --full-isolation` | Allowed; the project workspace is the OpenShell workspace |
| `--openshell --full-isolation --disk-name DISK` | Allowed; volume backing stays on the external disk |
| `--openshell --privileged` | Error: OpenShell sandboxes are non-root and cannot receive the Docker socket |
| `--openshell --fresh` | Error in the first release: no stack means no inference |
| `--openshell --restart` | Error: no agent starts |

Error text for the `--privileged` case must name the trade-off rather than the
syntax:

> `--privileged` grants the agent the Docker socket and root; OpenShell sandboxes
> are non-root and cannot receive it. Pick one: `--openshell` for a confined
> agent, or `--privileged` for an agent that spawns containers.

## 6. Runtime placement (open decision)

Two placements are viable; both keep the entrypoint as the sandbox's first
process.

- **A — client on the host.** `start.sh` branches to an internal helper that
  talks to the gateway. Cost: the OpenShell CLI must exist on the host.
- **B — client in a compose container.** The gateway is a compose service and
  an agent service runs the CLI as a controller. Benefit: the host needs only
  Docker. Cost: two containers per launch, and the TUI travels
  controller → gateway → sandbox.

**Recommended: A now, B only if "host needs nothing but Docker" becomes a
requirement.**

## 7. Workspace and volume admission

Admission is dynamic. It mirrors what the compose files already declare instead
of keeping a second list of volumes in the OpenShell path.

1. **Resolve** with the same compose file and project name the run uses:
   `docker compose -f "$COMPOSE" -p "$NAME_SUFFIX" config --format json`, then
   `docker volume inspect` for each resolved volume. The invocation must carry
   `PWD="$ORIG_PWD"` so the bind `device` resolves to the caller's directory.
2. **Admit** each volume the agent service mounts: if it carries
   `openshell.ai/sandbox-attachable=true` and
   `openshell.ai/sandbox-attachable-workspace=<workspace>`, mount it as-is.
3. **Twin** the rest: create a deterministic, labeled volume
   `<project>_openshell_<volume>` whose backing is the same one the compose
   volume uses — the bind `device` when present, otherwise the named volume's
   `Mountpoint` from `docker volume inspect`. The second case is a local-driver
   detail and must fail loudly if the driver is not `local`, rather than
   mounting an empty directory.
4. **Verify** an existing twin's `device` against the current cwd and recreate
   it on mismatch. Recreating a bind-backed volume removes a mount definition,
   not user files; named volumes are never recreated.

New volumes should carry the admission labels in the compose files themselves,
with `openshell.ai/sandbox-attachable-workspace=${NAME_SUFFIX:-common}`, so the
twin path is only a fallback for volumes created before the change. A guard
must assert that every volume an agent service mounts is either labeled or
covered by the twin rule.

The project mounts at a subdirectory of the sandbox workspace
(`/workspace/repo`), because a mount cannot replace the workspace root. The
entrypoint does `cd "${CODE_INFERENCE_WORKSPACE:-/workspace}"` before exec so
the agent starts in the project, and sandbox creation passes
`--env CODE_INFERENCE_WORKSPACE=/workspace/repo`.

## 8. Network and inference

- The sandbox reaches the PII gateway at `host.docker.internal:8000`, not
  `api:8000`; the compose network is not available to it.
- The policy endpoint pins `allowed_ips` to the Docker Desktop subnet and sets
  `tls: skip`, since the API speaks plain HTTP.
- Inference is not exposed directly to the sandbox. Masking, truncation, and
  the `X-Prompt-*` headers stay on the only path to the model.
- Gateway supervisors run in bridge mode by default, so Docker Desktop host
  networking does not have to be enabled.

## 9. SSH and git

HTTPS remotes and personal access tokens are not used. SSH remains the only git
transport; the policy allows `github.com:22` and `ssh.github.com:443` with
`protocol: tcp` and `tls: skip` (the server speaks first).

Credential delivery, in order of preference:

1. **Agent forwarding**: mount the host's `$SSH_AUTH_SOCK`; the agent can sign
   but cannot read the key. Best available posture, and the one the spike must
   prove on macOS.
2. **Read-only key mount**: the same exposure as today's `~/.ssh` mount. No
   regression, but no improvement on this axis either.
3. **Not used**: host-side push. A sandbox-written `.git/hooks/pre-push` would
   execute on the host, which is worse than handing over a key.

`known_hosts` is either baked into the image or populated by `ssh-keyscan`
under the same egress rule.

## 10. cwd contract

`--openshell` keeps today's rule: the workspace is the directory the command is
run from, never the install directory.

- The helper resolves compose files relative to the install directory and
  passes `PWD="$ORIG_PWD"` to both `docker compose config` and `docker compose
  up`. Omitting it on `config` silently resolves the workspace to the install
  directory.
- The project name from compose (normalised, not raw `basename`) selects the
  OpenShell workspace, the twin names, and the sandbox name, so two terminals
  in two folders do not collide.
- Nothing is read from or written to `~/.code-inference` as project state; that
  path holds the gateway and policies only.

## 11. Security posture

- The gateway holds the Docker socket. That is a control-plane trust shift and
  must be documented as such; it does not grant the agent anything.
- Telemetry is disabled for our gateway (`OPENSHELL_TELEMETRY_ENABLED=false`).
- The OpenShell version is pinned in the launcher and surfaced as
  `OPENSHELL_VERSION`, alongside `SKILLS_CLI` and the other pinned tools.
- Policy files live in the repository (`src/openshell/policies/<agent>.yaml`),
  so egress changes are reviewable and diffable rather than implicit.

## 12. Open questions

| Question | Default if unanswered |
| --- | --- |
| Placement A or B | A |
| SSH forwarding first, key mount as fallback | Yes |
| First scope | `opencode`, then `claude`, then the rest |
| OpenShell CLI handling | Pin and auto-install, like `skills@1.7.4` |
| Platform scope | macOS first, code kept platform-neutral |
| Long-term posture | Opt-in hardening tier, not the default boundary |

## 13. Plan

### Phase 0 — Spike, no feature code

Manual run on a scratch project. Exit criterion: every checkpoint passes, or
the result is documented and the feature stops.

1. Gateway on macOS Docker Desktop in bridge mode, pinned, telemetry off.
2. Our image built with `OPENCODE_VERSION`; `entrypoint.sh opencode` as main
   process; non-root user works.
3. Admitted or twinned volume at `/workspace/repo`; host and sandbox edits both
   visible; `docker compose config` exposes the bind `device`; a twin from a
   named volume's `Mountpoint` is admitted.
4. `api` reachable at `host.docker.internal:8000` with `allowed_ips`;
   `X-Prompt-Pii-Masked` still present.
5. `SSH_AUTH_SOCK` survives macOS → Docker Desktop → sandbox; `git push`
   works.
6. `--no-keep` gives `docker compose run --rm` semantics; the TUI is usable
   when attached; `-c` resumes a session through `opencode_data`.

The runbook belongs in `docs/openshell-spike.md` when Phase 0 starts.

### Phase 1 — `--openshell` for opencode

- `start.sh`: parse and validate the matrix, dispatch, help text, examples.
- Gateway lifecycle and workspace selection, idempotent.
- Image build and tag with the version pin.
- `src/openshell/policies/opencode.yaml`.
- Dynamic admission module plus admission labels in the compose files.
- `entrypoint.sh`: sandbox marker, `CODE_INFERENCE_WORKSPACE`, no root
  assumptions.
- Sandbox lifecycle: create, attach, exit code, cleanup, naming, concurrent
  runs.
- Docs (`docs/openshell.md` becomes the reference, plus `docs/settings.md`,
  `docs/agents.md`, `README.md`, `AGENTS.md`), a guard for unlabeled volumes,
  and a minor version bump.

### Phase 2 — Auth and the remaining agents

`claude`, then the rest; per-agent policies; cloud credentials through
providers, separate from git; per-agent session continuity.

### Phase 3 — Optional

Controller-container placement (B) if the host-CLI dependency becomes a
problem; OCSF export; policy advisor workflow; `--fresh` support.

### Phase 4 — Posture

Decide whether OpenShell becomes the default boundary. This plan does not
prejudge it; Phase 1 is deliberately opt-in and default-off.

## 14. Non-goals

- Privileged or nested sandboxes.
- Joining the compose `internal` network.
- Reimplementing the OpenShell CLI.
- Upload/download as the default workspace model.
- HTTPS git remotes or personal access tokens.

## 15. References

- OpenShell overview: <https://docs.nvidia.com/openshell/latest/about/overview>
- Architecture: <https://docs.nvidia.com/openshell/latest/about/architecture>
- Sandboxes: <https://docs.nvidia.com/openshell/latest/how-it-works/sandboxes/overview>
- Runtimes and Docker driver: <https://docs.nvidia.com/openshell/latest/how-it-works/sandboxes/runtimes>
- Network rules: <https://docs.nvidia.com/openshell/latest/how-it-works/policies/network-rules>
- Gateway as a container: <https://docs.nvidia.com/openshell/latest/how-it-works/gateways/container-deployment>
- Workspaces: <https://docs.nvidia.com/openshell/latest/how-it-works/workspaces>
- Inference: <https://docs.nvidia.com/openshell/latest/how-it-works/inference>
