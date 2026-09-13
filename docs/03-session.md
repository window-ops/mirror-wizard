# 3. Session setup

Run first in every new shell. All later pages assume these variables exist.

```bash
read -rs -p "GitLab token: " GITLAB_TOKEN && export GITLAB_TOKEN && echo
read -rs -p "GitHub token: " GITHUB_TOKEN && export GITHUB_TOKEN && echo
export GITLAB_HOST="gitlab.com"
export GITLAB_SELECTOR="owned=true"
export GITHUB_KIND="user"
export PROJECT_FILE="projects.tsv"
export EXCLUDE_FILE="exclude.txt"
touch "$EXCLUDE_FILE"
```

## Resolve the GitHub owner

Personal account:

```bash
export GITHUB_OWNER=$(curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/user | jq -r .login)
echo "$GITHUB_OWNER"
```

Organization:

```bash
export GITHUB_OWNER="my-org"
export GITHUB_KIND="org"
```

## Confirm the GitLab token

```bash
curl -sf --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/user" | jq -r .username
```

A username prints on success. Empty output means the token is invalid or lacks `api`.

---

Previous: [Prerequisites](02-prerequisites.md) | Next: [Build the project list](10-project-list.md)
