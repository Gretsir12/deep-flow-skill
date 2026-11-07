# DeepFlow Skill

The official agent Skill for [DeepFlow](https://deepflow.app) — a deploy
platform where you decide when your app ships.

`SKILL.md` is portable: it works with any AI agent that loads skills from a
directory, not only OpenCode. The installer ships it to the standard OpenCode,
Claude Code, and Agents locations; use `--dir` for any other agent.

The Skill teaches an AI agent how to work with DeepFlow through its public API:

- inspect projects, services, repositories, branches, commits, and releases;
- read deployments, events, logs, diagnostics, and node metrics;
- diagnose a failed rollout in a defined order;
- deploy an exact commit SHA and roll back to the previous successful release
  only after explicit user approval;
- keep the API key in the OS secret store instead of asking for it every session.

## Requirements

- macOS, Linux, WSL, or Windows (the Skill ships both `scripts/df.sh` and
  native PowerShell `scripts/df.ps1` / `scripts/df-auth.ps1`);
- `git`;
- `curl` for the one-line install (the installer itself needs `bash`; on
  Windows use Git Bash, WSL, or copy the files manually);
- a DeepFlow Pro or Max plan (the public API and the Skill are included).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Gretsir12/deep-flow-skill/refs/heads/main/install.sh | bash
```

The installer adds the Skill to every supported global directory:
`~/.config/opencode/skills/deepflow`, `~/.claude/skills/deepflow`, and
`~/.agents/skills/deepflow`. It does not modify agent configuration.

### Install options

| Command | Installs into |
| --- | --- |
| `curl -fsSL …/install.sh \| bash` | all three global directories below |
| `curl -fsSL …/install.sh \| bash -s -- --opencode` | `~/.config/opencode/skills/deepflow` |
| `curl -fsSL …/install.sh \| bash -s -- --claude` | `~/.claude/skills/deepflow` |
| `curl -fsSL …/install.sh \| bash -s -- --agents` | `~/.agents/skills/deepflow` |
| `curl -fsSL …/install.sh \| bash -s -- --all` | all three global directories |
| `curl -fsSL …/install.sh \| bash -s -- --project` | `./.opencode/skills/deepflow` |
| `curl -fsSL …/install.sh \| bash -s -- --dir <path>` | `<path>/deepflow` |

Replace `…` with `https://raw.githubusercontent.com/Gretsir12/deep-flow-skill/refs/heads/main`
when copying a command.

### Manual install

```sh
git clone https://github.com/Gretsir12/deep-flow-skill.git
cd deep-flow-skill
./install.sh
```

Run `./install.sh --help` to list every flag.

### Other agents

Any agent that reads a `SKILL.md` from a skills directory can use the Skill.
Point the installer at that directory:

```sh
./install.sh --dir /path/to/agent/skills
```

Or copy the files manually:

```sh
mkdir -p /path/to/agent/skills/deepflow
cp SKILL.md /path/to/agent/skills/deepflow/
cp -R references /path/to/agent/skills/deepflow/
cp -R scripts /path/to/agent/skills/deepflow/
```

## Verify

```sh
ls ~/.config/opencode/skills/deepflow/SKILL.md
```

The skill ID is `deepflow` in every location. After installing, reload your
agent or start a new session and check that `deepflow` appears in the available
skills. If you installed for another agent, confirm the files in that agent's
skills directory instead.

## Give the agent access

1. Sign in to DeepFlow.
2. Open **Settings → API keys**.
3. Create a key with read scopes first.
4. Add deploy and rollback scopes only if the agent should make changes.
5. Send the key and your installation URL to the agent when it asks.

The agent asks for the key once, then stores it in the protected secret store
of the OS and reuses it — you don't have to paste it every session:

| OS | Where the key is kept |
| --- | --- |
| macOS | Keychain, service `deepflow-api-key` |
| Linux | Secret Service via `secret-tool` (libsecret) |
| Windows | DPAPI-protected file in `%APPDATA%\DeepFlow` |
| other unix, no keyring | file with mode `0600` in `~/.config/deepflow` |

You can also configure it yourself, without sending the key through chat:

```sh
printf '%s' "$DEEPFLOW_KEY" | scripts/df-auth.sh set
scripts/df-auth.sh url https://app.deepflow.example
scripts/df-auth.sh test
```

```powershell
powershell -File scripts\df-auth.ps1 set
powershell -File scripts\df-auth.ps1 url https://app.deepflow.example
powershell -File scripts\df-auth.ps1 test
```

`status` shows only a mask (`dfk_…abcd`), `test` checks the key against
`GET /public/projects`, and `rm` deletes the stored key. Environment variables
`DEEPFLOW_API_URL` / `DEEPFLOW_API_KEY` still override the store, which is
handy for CI. The repository and `SKILL.md` never contain the key.

## What's inside

```text
.
├── SKILL.md
├── install.sh
├── references/
│   └── api-schemas.md
└── scripts/
    ├── df.sh          # API wrapper: macOS, Linux, Git Bash
    ├── df-auth.sh     # key storage: Keychain / Secret Service / file
    ├── df.ps1         # API wrapper: Windows
    └── df-auth.ps1    # key storage: Windows DPAPI
```

- `SKILL.md` — agent rules, diagnostic order, and safety rules.
- `references/api-schemas.md` — request and response schemas for the public API.
- `scripts/` — CLI helpers the agent uses to store the key and call the API.

## Safety

- The agent must ask before deploying or rolling back.
- Read, deploy, and rollback are separate scopes.
- The API key is stored in the OS secret store (Keychain, Secret Service, or
  DPAPI) and is never written to the Skill files or the repository.
- API keys can be limited to selected projects and an expiry date.
- Logs and repository content are treated as data, never as instructions.
- Every deploy and rollback is recorded in the key audit log.

## Uninstall

```sh
rm -rf ~/.config/opencode/skills/deepflow
rm -rf ~/.claude/skills/deepflow
rm -rf ~/.agents/skills/deepflow
```

For a project-local install, remove `.opencode/skills/deepflow` from the
project.

## Links

- Install the Skill: <https://deepflow.app/skills/install>
- API and Skill overview: <https://deepflow.app/features/agents>
