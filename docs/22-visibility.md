# G. Correct repository visibility

Two uses: repairing repositories created without the JSON content type, and realigning GitHub after
a visibility change on GitLab.

```bash
: > visfix.log
while IFS=$'\t' read -r id path full vis; do
  case "$vis" in public) priv=false ;; *) priv=true ;; esac
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 -X PATCH \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/$GITHUB_OWNER/$path" \
    -d "$(jq -nc --argjson p $priv '{private:$p}')")
  printf '%s\t%s\n' "$path" "$code" >> visfix.log
  sleep 1
done < "$PROJECT_FILE"
awk -F'\t' '$2!=200' visfix.log
```

Confirm one repository:

```bash
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GITHUB_OWNER/REPO_NAME" | jq '{private, visibility}'
```

| Code | Meaning | Action |
|---|---|---|
| `200` | Updated | Done |
| `422` | Organization member privilege blocks visibility changes | Adjust the organization setting, or change it through the web interface |
| `403` | Account restricted from private repositories | Keep the repository public |

Forks of a public repository stay public after the parent turns private.

---

Reference: [Create GitHub repositories](11-create-repos.md) | [Back to start](../README.md)
