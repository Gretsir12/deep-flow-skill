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
  only after explicit user approval.

## Requirements

- macOS, Linux, or WSL;
- `git`;
- `curl` for the one-line install;
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
5. Give the key to the agent through its environment or secret store, never in
   chat.

The agent reads the key from its environment. The Skill never stores the token.

## What's inside

```text
.
├── SKILL.md
├── install.sh
└── references/
    └── api-schemas.md
```

- `SKILL.md` — agent rules, diagnostic order, and safety rules.
- `references/api-schemas.md` — request and response schemas for the public API.

## Safety

- The agent must ask before deploying or rolling back.
- Read, deploy, and rollback are separate scopes.
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
