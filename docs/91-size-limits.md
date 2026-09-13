# Size limits

GitHub rejects individual files above 100 MB and warns above 50 MB. A single push tops out near
2 GB. A soft repository ceiling sits around 5 GB. GitLab mirrors always attempt one push, so a
repository past the push limit can never mirror as configured.

## Measure

```bash
curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects/PROJECT_ID?statistics=true" \
  | jq '{repository_size_mb: (.statistics.repository_size/1048576|floor),
         lfs_mb: (.statistics.lfs_objects_size/1048576|floor)}'
```

Project IDs are the first column of `$PROJECT_FILE`.

## Resolutions

### Exclude

Delete the mirror, add the repository name to `$EXCLUDE_FILE`, rerun
[build the project list](10-project-list.md).

```bash
mid=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects/PROJECT_ID/remote_mirrors" | jq -r '.[0].id')
curl -s -o /dev/null -w '%{http_code}\n' -X DELETE \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects/PROJECT_ID/remote_mirrors/$mid"
```

`204` confirms deletion. The empty GitHub repository can be removed through the web interface,
which needs no token scope.

### Seed manually

Clone locally, push history to GitHub in batches so no single push approaches the limit, then
create the mirror to handle increments from that point. Transfer cost equals the repository size in
both directions.

### Shrink

Identify large blobs, rewrite history with `git filter-repo`, or migrate blobs to Git LFS. Rewriting
changes every commit hash on GitLab as well, which affects anyone who cloned the project.

---

Reference: [Failure symptoms](90-failures.md) | [Constraints](92-constraints.md)
