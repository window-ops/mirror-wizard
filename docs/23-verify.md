# H. Verify content

The GitHub `size` field updates through a background job and reports `0` on a populated repository
for some minutes after a push. Query refs instead.

```bash
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GITHUB_OWNER/REPO_NAME/commits?per_page=1" \
  | jq -r 'if type=="array" then (.[0].sha // "empty") else .message end'
```

Across the whole list:

```bash
while IFS=$'\t' read -r id path full vis; do
  sha=$(curl -s --connect-timeout 10 --max-time 30 -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_OWNER/$path/commits?per_page=1" \
    | jq -r 'if type=="array" then (.[0].sha // "empty") else .message end')
  printf '%s\t%s\n' "$path" "$sha"
  sleep 1
done < "$PROJECT_FILE" | grep -v -E '\t[0-9a-f]{40}$'
```

Output lists only the repositories without commits.

| Result | Action |
|---|---|
| Commit SHA | Content arrived |
| `empty`, source project has commits | Return to [read mirror status](20-status.md) |
| `empty`, source project is empty on GitLab | Expected |
| `Not Found` | Repository missing or renamed. Run [create GitHub repositories](11-create-repos.md) for that row |

---

Reference: [Read mirror status](20-status.md) | [Back to start](../README.md)
