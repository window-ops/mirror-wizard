# C. Create mirrors

The GitHub token becomes part of each mirror URL. GitLab encrypts it at rest and redacts it from
API responses.

```bash
: > mirrors.log
while IFS=$'\t' read -r id path full vis; do
  url="https://$GITHUB_OWNER:$GITHUB_TOKEN@github.com/$GITHUB_OWNER/$path.git"
  code=$(curl -s -o gl_resp.json -w '%{http_code}' --connect-timeout 10 --max-time 30 -X POST \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors" \
    -d "$(jq -nc --arg u "$url" '{url:$u,enabled:true,only_protected_branches:false}')")
  printf '%s\t%s\t%s\n' "$path" "$code" "$(jq -r '.message // .error // "ok"' gl_resp.json)" >> mirrors.log
  sleep 1
done < "$PROJECT_FILE"
wc -l < mirrors.log && awk -F'\t' '$2!=201' mirrors.log
```

When the token owner differs from the repository owner, as with an organization target, put the
authenticated GitHub username in the credential position and leave the path on `$GITHUB_OWNER`:

```bash
url="https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_OWNER/$path.git"
```

## Options

| Field | Effect |
|---|---|
| `only_protected_branches` | `true` restricts the mirror to protected branches |
| `keep_divergent_refs` | `true` skips refs that diverged on GitHub instead of overwriting them |
| `mirror_branch_regex` | Limits mirroring to matching branch names. Premium and Ultimate only |

`keep_divergent_refs` is settable only through the API after creation.

| Code | Action |
|---|---|
| `201` | Continue to [force initial sync](13-sync.md) |
| `400` or `422` | Read the message column in `mirrors.log`, usually a malformed URL |

---

Previous: [Create GitHub repositories](11-create-repos.md) | Next: [Force initial sync](13-sync.md)
