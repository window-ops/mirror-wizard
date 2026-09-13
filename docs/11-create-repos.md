# B. Create GitHub repositories

Visibility follows the GitLab value. GitLab `internal` and `private` both map to private.

`Content-Type: application/json` is mandatory. Without it curl sends form-encoded data. GitHub
still reads the repository name and applies its private default to the boolean, returning `201`
with no error. [Correct visibility](22-visibility.md) repairs that result.

```bash
case "$GITHUB_KIND" in
  org) create_url="https://api.github.com/orgs/$GITHUB_OWNER/repos" ;;
  *)   create_url="https://api.github.com/user/repos" ;;
esac
: > created.log
while IFS=$'\t' read -r id path full vis; do
  case "$vis" in public) priv=false ;; *) priv=true ;; esac
  code=$(curl -s -o gh_resp.json -w '%{http_code}' --connect-timeout 10 --max-time 30 -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    "$create_url" \
    -d "$(jq -nc --arg n "$path" --argjson p $priv '{name:$n,private:$p,has_issues:false,has_wiki:false}')")
  printf '%s\t%s\t%s\n' "$path" "$code" "$(jq -r '.message // "ok"' gh_resp.json)" >> created.log
  sleep 1
done < "$PROJECT_FILE"
wc -l < created.log && awk -F'\t' '$2!=201' created.log
```

`has_issues:false` keeps contributors pointed at the GitLab tracker. Drop it to accept issues on
the GitHub side.

| Code | Meaning | Action |
|---|---|---|
| `201` | Created | Continue to [create mirrors](12-create-mirrors.md) |
| `422`, name already exists | Repository predates this run | Continue, the existing repository is reused |
| `403` | Token lacks `repo`, or no creation rights in the organization | Reissue the token, see [parameters](01-parameters.md) |
| Line count below `$PROJECT_FILE` | Loop interrupted | Resume, see [failures](90-failures.md) |

---

Previous: [Build the project list](10-project-list.md) | Next: [Create mirrors](12-create-mirrors.md)
