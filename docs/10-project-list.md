# A. Build the project list

`$PROJECT_FILE` has four tab-separated columns: GitLab project ID, repository name, full namespace
path, visibility. Regenerating it takes about a minute, so the file is disposable.

```bash
: > "$PROJECT_FILE"
page=1
while :; do
  resp=$(curl -sf --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects?$GITLAB_SELECTOR&per_page=100&page=$page&order_by=id&sort=asc")
  [ "$(printf '%s' "$resp" | jq 'length')" -eq 0 ] && break
  printf '%s' "$resp" | jq -r '.[] | [.id, .path, .path_with_namespace, .visibility] | @tsv' >> "$PROJECT_FILE"
  page=$((page+1))
done
wc -l < "$PROJECT_FILE"
```

## Apply exclusions

```bash
awk -F'\t' 'NR==FNR{skip[$1];next} !($2 in skip)' "$EXCLUDE_FILE" "$PROJECT_FILE" > .filtered \
  && mv .filtered "$PROJECT_FILE"
wc -l < "$PROJECT_FILE"
```

## Detect name collisions

Two GitLab projects under different namespaces may share a repository name. A single GitHub owner
accepts that name once.

```bash
cut -f2 "$PROJECT_FILE" | sort | uniq -d
```

| Result | Action |
|---|---|
| Empty output | Continue to [create GitHub repositories](11-create-repos.md) |
| One or more names | Rename one project on GitLab, or add the name to `$EXCLUDE_FILE` and rerun this page |

## Filter to a single project

For the incremental path:

```bash
grep -P '\tPROJECT_NAME\t' "$PROJECT_FILE" > one.tsv
```

Without `grep -P`:

```bash
awk -F'\t' '$2=="PROJECT_NAME"' "$PROJECT_FILE" > one.tsv
```

Substitute `one.tsv` wherever a loop reads `"$PROJECT_FILE"`.

---

Previous: [Session setup](03-session.md) | Next: [Create GitHub repositories](11-create-repos.md)
