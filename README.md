# GitLab to GitHub push mirroring

One-way push mirroring from GitLab projects to GitHub repositories, using the GitLab remote mirrors
API and the GitHub repositories API. GitLab stays canonical. GitHub receives copies.

Applies to gitlab.com and to self-managed GitLab 16.11 or later. Targets a GitHub personal account
or an organization.

## Start here

Read [parameters](docs/01-parameters.md), [prerequisites](docs/02-prerequisites.md) and
[session setup](docs/03-session.md) once. Then pick the situation.

| Situation | Go to |
|---|---|
| First-time setup | [Build the project list](docs/10-project-list.md) |
| Mirrors failing, cause unknown | [Read mirror status](docs/20-status.md) |
| GitHub token replaced or revoked | [Rebuild mirrors](docs/21-rebuild.md) |
| GitHub repositories deleted, GitLab mirrors intact | [Create GitHub repositories](docs/11-create-repos.md) |
| New GitLab project added | [Build the project list](docs/10-project-list.md) |
| Repositories created with the wrong visibility | [Correct visibility](docs/22-visibility.md) |
| Sync reported success, GitHub appears empty | [Verify content](docs/23-verify.md) |
| A repository is too large to push | [Size limits](docs/91-size-limits.md) |

## Reference

- [Failure symptoms](docs/90-failures.md)
- [Constraints](docs/92-constraints.md)
