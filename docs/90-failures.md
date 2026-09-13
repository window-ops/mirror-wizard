# Failure symptoms

Match the message from the third column of `status.log`, produced by
[read mirror status](20-status.md).

| Symptom | Cause | Fix |
|---|---|---|
| Authentication failure on every project | GitHub token expired, revoked, or scope reduced | Issue a replacement with `repo`, then [rebuild](21-rebuild.md), then [sync](13-sync.md) |
| Authentication failure on one project | Repository renamed or deleted on GitHub | [Create GitHub repositories](11-create-repos.md) filtered to that row, then [rebuild](21-rebuild.md) |
| `HTTP 500`, `unexpected disconnect while reading sideband packet` | Repository exceeds GitHub's single-push capacity | [Size limits](91-size-limits.md) |
| `repository not found` | Wrong owner in the URL, or a collision resolved for another project | Recheck collisions in [build the project list](10-project-list.md) |
| Mirror absent from the API response | Creation never succeeded | Rerun [create mirrors](12-create-mirrors.md) for that row |
| `update failed`, divergent refs | Commits made directly on GitHub | Reset the GitHub branch, or enable `keep_divergent_refs` |
| File over 100 MB rejected | GitHub file size limit | [Size limits](91-size-limits.md) |

## Interrupted loop

Every loop appends one line per project, so the log doubles as a resume point.

```bash
cut -f1 LOGFILE | sort > .done.txt
cut -f2 "$PROJECT_FILE" | sort | comm -23 - .done.txt > remaining.txt
wc -l < remaining.txt
```

Build a filtered project file from the remainder, then rerun the loop against it:

```bash
awk -F'\t' 'NR==FNR{want[$1];next} ($2 in want)' remaining.txt "$PROJECT_FILE" > retry.tsv
```

## Frozen terminal on Git Bash

Ctrl+C sometimes fails to reach curl, leaving the window unresponsive. Close it, open a new one,
rerun [session setup](03-session.md), then resume as above. Loops have
`--connect-timeout 10 --max-time 30` to limit time at any single stalled request.

---

Reference: [Read mirror status](20-status.md) | [Constraints](92-constraints.md)
