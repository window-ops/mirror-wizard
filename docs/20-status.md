# E. Read mirror status

```bash
: > status.log
while IFS=$'\t' read -r id path full vis; do
  curl -s --connect-timeout 10 --max-time 30 --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors" \
    | jq -r --arg p "$path" '.[0] | [$p, .update_status, (.last_error // "none")] | @tsv' >> status.log
  sleep 1
done < "$PROJECT_FILE"
awk -F'\t' '$2!="finished"' status.log
```

`update_status` takes the values `none`, `scheduled`, `started`, `finished` and `failed`.

| Result | Action |
|---|---|
| No output | Every mirror completed. Spot-check with [verify content](23-verify.md) |
| `scheduled` or `started` | Pushes still running. Wait, then rerun this page |
| `to_retry` or `failed` | Match the message against [failure symptoms](90-failures.md) |
| `none` | Never synced. Run [force initial sync](13-sync.md) |

Count the successes:

```bash
awk -F'\t' '$2=="finished"' status.log | wc -l
```

---

Previous: [Force initial sync](13-sync.md) | Reference: [Failure symptoms](90-failures.md)
