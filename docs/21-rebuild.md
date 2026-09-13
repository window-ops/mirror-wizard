# F. Rebuild mirrors after a token change

`PUT /projects/:id/remote_mirrors/:mirror_id` accepts `enabled`, `only_protected_branches`,
`keep_divergent_refs`, `mirror_branch_regex` and `auth_method`. The `url` field is outside that set,
so changing an embedded credential means deleting the mirror and creating a replacement.

Prerequisite: a replacement GitHub token exported in the current shell, per
[session setup](03-session.md).

```bash
: > rebuild.log
while IFS=$'\t' read -r id path full vis; do
  mid=$(curl -s --connect-timeout 10 --max-time 30 --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors" | jq -r '.[0].id // empty')
  [ -n "$mid" ] && curl -s -o /dev/null -X DELETE --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors/$mid"
  url="https://$GITHUB_OWNER:$GITHUB_TOKEN@github.com/$GITHUB_OWNER/$path.git"
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 -X POST \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "Content-Type: application/json" \
    "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors" \
    -d "$(jq -nc --arg u "$url" '{url:$u,enabled:true,only_protected_branches:false}')")
  printf '%s\t%s\n' "$path" "$code" >> rebuild.log
  sleep 1
done < "$PROJECT_FILE"
awk -F'\t' '$2!=201' rebuild.log
```

| Code | Action |
|---|---|
| `201` | Run [force initial sync](13-sync.md) so commits from the outage reach GitHub |
| Anything else | Inspect that project through [read mirror status](20-status.md) |

Deleting a mirror removes no content from GitHub. The GitHub repository keeps whatever the last
successful push delivered.

---

Reference: [Read mirror status](20-status.md) | Next: [Force initial sync](13-sync.md)
