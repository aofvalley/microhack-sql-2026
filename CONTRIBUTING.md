# Contributing

Thank you for contributing to **microhack-sql-2026**!

## Quick start

1. Fork and clone the repo.
2. Create a feature branch from `main`: `git checkout -b feat/my-change`.
3. Make your changes, then run the linters locally (see below).
4. Open a Pull Request against `main`.

## Local lint checks

```powershell
# PowerShell (requires PSScriptAnalyzer)
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Severity Warning,Error

# Markdown (requires Node.js)
npm install -g markdownlint-cli
markdownlint '**/*.md' --ignore node_modules --config .markdownlint.yml
```

Both checks also run in CI on every push and PR.

## Conventions

| Area | Convention |
| --- | --- |
| PowerShell | Use `[CmdletBinding()]` on all functions; PSScriptAnalyzer-clean |
| Bicep | One module per resource type; parameters aligned with `deploy.ps1` |
| Markdown | Max line length 200; no bare HTML |
| Secrets | Never commit real passwords, tenant IDs, or subscription IDs |

## Commit messages

Use the imperative mood: `Add budget alert module`, not `Added budget alerts`.
