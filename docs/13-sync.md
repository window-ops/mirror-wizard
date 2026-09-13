# D. Force initial sync

A new mirror transmits when commits arrive, so existing history needs an explicit trigger. The sync
endpoint was introduced in GitLab 16.11.

```bash
: > sync.log
while IFS=$'\t' read -r id path full vis; do
  mid=$(curl -s --connect-timeout 10 --max-time 30 --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors" | jq -r '.[0].id // empty')
  if [ -z "$mid" ]; then printf '%s\tnomirror\n' "$path" >> sync.log; continue; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 -X POST \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors/$mid/sync")
  printf '%s\t%s\n' "$path" "$code" >> sync.log
  sleep 1
done < "$PROJECT_FILE"
wc -l < sync.log && awk -F'\t' '$2!=204' sync.log
```

Pushes proceed asynchronously after the request returns.

| Code | Meaning | Action |
|---|---|---|
| `204` | Accepted | Wait several minutes, then [read mirror status](20-status.md) |
| `404` | GitLab older than 16.11 | Push a commit to GitLab, or use Update now under Settings, Repository, Mirroring repositories |
| `nomirror` | No mirror on that project | Rerun [create mirrors](12-create-mirrors.md) for that row |

---

Previous: [Create mirrors](12-create-mirrors.md) | Next: [Read mirror status](20-status.md)
