# I. Add one project

Covers a single new project without enumerating the full list. Substitutes a known project ID and
repository name for `$PROJECT_FILE`. Requires [session setup](03-session.md).

Set the name once:

```bash
export NAME="mirror-wizard"
```

## 1. Get or create the GitLab project

If it exists already:

```bash
export PID=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects?owned=true&search=$NAME" \
  | jq -r --arg n "$NAME" '.[] | select(.path==$n) | .id')
echo "$PID"
```

If it does not:

```bash
export PID=$(curl -s -X POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  "https://$GITLAB_HOST/api/v4/projects" \
  -d "$(jq -nc --arg n "$NAME" '{name:$n,path:$n,visibility:"public",initialize_with_readme:false}')" \
  | jq -r .id)
echo "$PID"
```

Change `visibility` to `private` where appropriate. Add `"namespace_id": NNN` to place the project
in a group.

An empty `$PID` at this point stops the procedure. Recheck `GITLAB_HOST` and the token.

## 2. Push local content

Skip when the project already has commits.

```bash
git remote add origin "https://$GITLAB_HOST/$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects/$PID" | jq -r .path_with_namespace).git"
git push -u origin main
```

## 3. Create the GitHub repository

```bash
case "$GITHUB_KIND" in
  org) create_url="https://api.github.com/orgs/$GITHUB_OWNER/repos" ;;
  *)   create_url="https://api.github.com/user/repos" ;;
esac
curl -s -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
  "$create_url" \
  -d "$(jq -nc --arg n "$NAME" '{name:$n,private:false,has_issues:false,has_wiki:false}')" \
  | jq '{full_name, private, message}'
```

Set `private` to `true` for a private GitLab project. The content type header is mandatory, for the
reason given in [create GitHub repositories](11-create-repos.md).

A `message` of `Repository creation failed` with a name-already-exists error means the repository is
present, which is harmless here.

## 4. Create the mirror

```bash
url="https://$GITHUB_OWNER:$GITHUB_TOKEN@github.com/$GITHUB_OWNER/$NAME.git"
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "Content-Type: application/json" \
  "https://$GITLAB_HOST/api/v4/projects/$PID/remote_mirrors" \
  -d "$(jq -nc --arg u "$url" '{url:$u,enabled:true,only_protected_branches:false}')"
```

`201` confirms creation. A `400` usually means a mirror already exists for that project.

## 5. Sync

```bash
mid=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects/$PID/remote_mirrors" | jq -r '.[0].id')
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects/$PID/remote_mirrors/$mid/sync"
```

`204` confirms the request. Skip this step when step 2 pushed commits, since that push triggers the
mirror on its own.

## 6. Verify

```bash
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GITHUB_OWNER/$NAME/commits?per_page=1" \
  | jq -r 'if type=="array" then (.[0].sha // "empty") else .message end'
```

A commit SHA ends the procedure. `empty` routes to [read mirror status](20-status.md), narrowed to
this project:

```bash
curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects/$PID/remote_mirrors" \
  | jq -r '.[0] | [.update_status, (.last_error // "none")] | @tsv'
```

## When to run the full list instead

| Condition | Path |
|---|---|
| One or two projects added | This page |
| Many projects added, or the list is stale | [Build the project list](10-project-list.md) |
| Name may collide with an existing repository | [Build the project list](10-project-list.md), collision section |
| Bulk token rotation needed | [Rebuild mirrors](21-rebuild.md), which needs the full list |

`$PROJECT_FILE` stays stale after this procedure. Regenerate it before any bulk operation.

---

Reference: [Build the project list](10-project-list.md) | [Back to start](../README.md)
