# Constraints

## Platform limits

- GitHub rejects individual files above 100 MB and warns above 50 MB.
- A single push tops out near 2 GB.
- GitHub applies a soft repository ceiling around 5 GB.
- GitHub throttles content-mutating requests separately from the documented rate limit. The
  `sleep 1` in each loop reflects roughly one write per second, against a ceiling near 500 writes
  per hour on a personal account.
- Expect 2 to 3 minutes per 50 projects per loop, dominated by that sleep.

## Design decisions

- `--connect-timeout 10 --max-time 30` bounds any single stalled request. Loops without them can
  hang indefinitely, and Git Bash may refuse Ctrl+C.
- Mirror jobs execute on GitLab infrastructure, triggered by pushes to GitLab. No local machine
  participates after setup.
- Pull mirroring, meaning GitHub to GitLab, requires GitLab Premium or Ultimate. Bidirectional
  configurations are documented as conflict-prone. This procedure covers push only.
- A GitHub token without an expiry date removes scheduled renewal. That token then persists inside
  every mirror URL, and any revocation, including automatic revocation by GitHub secret scanning
  after a leak, disables all mirrors at once. [Rebuild](21-rebuild.md) is the recovery path either
  way.

## Mirror notices on GitHub

GitHub has no native mirror indicator. A push mirror looks like any other repository. Projects that
display a notice produce it themselves:

- A block at the top of the README naming the canonical location. Written in the GitLab README, it
  propagates on the next push.
- The repository description, shown under the repository name.
- Issues and pull requests disabled in GitHub settings, which survives pushes.
  [Create GitHub repositories](11-create-repos.md) sets `has_issues:false` already.
- `CONTRIBUTING.md`, surfaced when someone opens a pull request.

Archiving produces a real GitHub banner and blocks all pushes, which ends mirroring.

---

Reference: [Failure symptoms](90-failures.md) | [Back to start](../README.md)
