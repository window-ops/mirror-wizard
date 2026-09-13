# 1. Parameters

Set per deployment.

| Variable | Meaning | Example |
|---|---|---|
| `GITLAB_HOST` | GitLab hostname, no scheme | `gitlab.com` |
| `GITLAB_SELECTOR` | Which projects to enumerate | `owned=true` or `membership=true` |
| `GITHUB_OWNER` | Account or organization receiving the copies | resolved in step 3 |
| `GITHUB_KIND` | `user` or `org`, selects the creation endpoint | `user` |
| `EXCLUDE_FILE` | One repository name per line, skipped everywhere | `exclude.txt` |
| `PROJECT_FILE` | Working list, four tab-separated columns | `projects.tsv` |

## Tokens

Tokens stay out of files and out of shell history. Step 3 reads them interactively.

| Token | Minimum scope | Used for |
|---|---|---|
| GitLab personal access token | `api` | project enumeration, mirror management |
| GitHub classic personal access token | `repo` | repository creation, mirror authentication |

`read_api` on the GitLab side is insufficient, since mirror creation is a POST.

Conditional scopes:

- `workflow` on the GitHub token when any repository includes a `.github/workflows` directory.
- `delete_repo` on the GitHub token only while removing repositories through the API. Remove it
  afterwards.

An organization target additionally requires repository creation rights for the authenticated
GitHub user in that organization.

The GitHub token becomes part of every mirror URL. Revoking it disables all mirrors at once, and
recovery runs through [rebuild](21-rebuild.md).

---

Next: [Prerequisites](02-prerequisites.md)
