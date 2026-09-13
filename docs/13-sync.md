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

GitLab rate-limits push mirror updates to about one every 5 minutes per project. A forced sync
inside that window returns `204` and the job is dropped, so the mirror keeps reporting `finished`
with an older `last_update_at`. The update arrives at the end of the interval without further
action. Compare the source commit against the mirrored ref before treating the delay as a fault:

```bash
curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects/PROJECT_ID/repository/branches/main" | jq -r '.commit.id'
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GITHUB_OWNER/REPO_NAME/git/refs/heads/main" | jq -r '.object.sha'
```

| Code | Meaning | Action |
|---|---|---|
| `204` | Accepted | Wait several minutes, then [read mirror status](20-status.md) |
| `204`, `last_update_at` unchanged | Inside the 5-minute interval | Wait for the interval to elapse |
| `404` | GitLab older than 16.11 | Push a commit to GitLab, or use Update now under Settings, Repository, Mirroring repositories |
| `nomirror` | No mirror on that project | Rerun [create mirrors](12-create-mirrors.md) for that row |

---

Previous: [Create mirrors](12-create-mirrors.md) | Next: [Read mirror status](20-status.md)
