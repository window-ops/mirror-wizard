#!/usr/bin/env bash
# Interactive setup and maintenance for GitLab to GitHub push mirroring.
# Implements the procedures in docs/. Tokens are read interactively and never written to disk.

set -u

WORKDIR="${MIRROR_WIZARD_DIR:-$PWD/.mirror-wizard}"
PROJECT_FILE="$WORKDIR/projects.tsv"
EXCLUDE_FILE="${EXCLUDE_FILE:-$PWD/exclude.txt}"
CURL_OPTS=(-s --connect-timeout 10 --max-time 30)
SLEEP_BETWEEN=1

GITLAB_HOST=""
GITLAB_TOKEN=""
GITLAB_SELECTOR="owned=true"
GITHUB_TOKEN=""
GITHUB_OWNER=""
GITHUB_USER=""
GITHUB_KIND="user"

# ---------------------------------------------------------------- output

WIZ_CAPTURE=0
WIZ_MSGS=""
SESSION_LOG="$WORKDIR/session.log"

# Appends one timestamped line to the session log. Never fails the caller.
# Field 1 is the timestamp, field 2 a five-character tag, field 3 the message.
logline() {
  [ -d "$WORKDIR" ] || return 0
  local tag="$1"; shift
  local msg="$*"
  msg="${msg#"${msg%%[![:space:]]*}"}"
  [ -n "$msg" ] || return 0
  printf '%s  %-5s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$tag" "$msg" >> "$SESSION_LOG" 2>/dev/null || true
}

say()  { logline SAY "$*"; printf '%s\n' "$*"; }
info() { logline INFO "$*"; printf '  %s\n' "$*"; }
warn() {
  logline WARN "$*"
  [ "$WIZ_CAPTURE" -eq 1 ] && WIZ_MSGS="${WIZ_MSGS}  $*"$'\n'
  printf '  [!] %s\n' "$*" >&2
}
die()  { logline FATAL "$*"; printf '  [x] %s\n' "$*" >&2; exit 1; }
rule() { printf '%s\n' "----------------------------------------------------------------"; }

# Clears the screen for a new panel. Inert when output is piped or redirected,
# which keeps logs and test runs readable.
cls() {
  [ -t 1 ] || return 0
  if command -v clear >/dev/null 2>&1; then clear; else printf '\033[2J\033[H'; fi
}

confirm() {
  local reply
  read -r -p "$1 [y/N] " reply
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------- setup

check_deps() {
  local missing=0
  for cmd in curl jq awk sort comm; do
    command -v "$cmd" >/dev/null 2>&1 || { warn "missing: $cmd"; missing=1; }
  done
  [ "$missing" -eq 0 ] || die "missing tools, listed in docs/02-prerequisites.md"
}

load_session() {
  mkdir -p "$WORKDIR"
  touch "$EXCLUDE_FILE"

  read -r -p "GitLab host [gitlab.com]: " GITLAB_HOST
  GITLAB_HOST="${GITLAB_HOST:-gitlab.com}"

  read -rs -p "GitLab token (api scope): " GITLAB_TOKEN; echo
  [ -n "$GITLAB_TOKEN" ] || { warn "no GitLab token given"; return 1; }

  local gl_user
  gl_user=$(curl "${CURL_OPTS[@]}" --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://$GITLAB_HOST/api/v4/user" | jq -r '.username // empty')
  [ -n "$gl_user" ] || { warn "GitLab token rejected by https://$GITLAB_HOST"; return 1; }
  info "GitLab user: $gl_user"

  read -rs -p "GitHub token (repo scope): " GITHUB_TOKEN; echo
  [ -n "$GITHUB_TOKEN" ] || { warn "no GitHub token given"; return 1; }

  GITHUB_USER=$(curl "${CURL_OPTS[@]}" -H "Authorization: Bearer $GITHUB_TOKEN" \
    https://api.github.com/user | jq -r '.login // empty')
  [ -n "$GITHUB_USER" ] || { warn "GitHub token rejected"; return 1; }
  info "GitHub user: $GITHUB_USER"

  local scopes
  scopes=$(curl "${CURL_OPTS[@]}" -I -H "Authorization: Bearer $GITHUB_TOKEN" \
    https://api.github.com/user | awk 'tolower($1)=="x-oauth-scopes:"{sub(/^[^:]*: */,"");print}' | tr -d '\r')
  case "$scopes" in
    *repo*) : ;;
    "")     warn "token scopes unreadable, a fine-grained token cannot be checked this way" ;;
    *)      warn "token scopes: $scopes. Repository creation and mirroring need repo" ;;
  esac

  local target
  read -r -p "GitHub target, user or org [user]: " target
  case "${target:-user}" in
    org|organization)
      GITHUB_KIND="org"
      read -r -p "Organization name: " GITHUB_OWNER
      [ -n "$GITHUB_OWNER" ] || { warn "no organization name given"; return 1; }
      ;;
    *)
      GITHUB_KIND="user"
      GITHUB_OWNER="$GITHUB_USER"
      ;;
  esac

  local sel
  read -r -p "Enumerate owned projects only, or all memberships? [owned/member]: " sel
  case "$sel" in member|membership) GITLAB_SELECTOR="membership=true" ;; *) GITLAB_SELECTOR="owned=true" ;; esac

  logline SESS "host=$GITLAB_HOST gl_user=$gl_user gh_user=$GITHUB_USER owner=$GITHUB_OWNER kind=$GITHUB_KIND selector=$GITLAB_SELECTOR"
  info "target: $GITHUB_OWNER ($GITHUB_KIND), selector: $GITLAB_SELECTOR"
  info "work directory: $WORKDIR"
}

require_session() {
  [ -n "$GITLAB_TOKEN" ] && [ -n "$GITHUB_TOKEN" ] && return 0
  warn "run step 1 first"
  return 1
}

require_list() {
  [ -s "$PROJECT_FILE" ] && return 0
  warn "no project list, run step 2 first"
  return 1
}

# ---------------------------------------------------------------- helpers

gh_create_url() {
  case "$GITHUB_KIND" in
    org) printf 'https://api.github.com/orgs/%s/repos' "$GITHUB_OWNER" ;;
    *)   printf 'https://api.github.com/user/repos' ;;
  esac
}

mirror_url() {
  printf 'https://%s:%s@github.com/%s/%s.git' "$GITHUB_USER" "$GITHUB_TOKEN" "$GITHUB_OWNER" "$1"
}

mirror_id_for() {
  curl "${CURL_OPTS[@]}" --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects/$1/remote_mirrors" | jq -r '.[0].id // empty'
}

progress() {
  printf '\r  %s %d/%d   ' "$1" "$2" "$3"
  [ "$2" -eq "$3" ] && printf '\n'
}

count_rows() { wc -l < "$PROJECT_FILE" | tr -d ' '; }

# ---------------------------------------------------------------- A. list

build_list() {
  require_session || return 1
  local page=1 resp len total=0
  : > "$PROJECT_FILE"
  say "Enumerating projects"
  while :; do
    resp=$(curl "${CURL_OPTS[@]}" --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      "https://$GITLAB_HOST/api/v4/projects?$GITLAB_SELECTOR&per_page=100&page=$page&order_by=id&sort=asc")
    len=$(printf '%s' "$resp" | jq 'if type=="array" then length else 0 end' 2>/dev/null || echo 0)
    [ "$len" -eq 0 ] && break
    printf '%s' "$resp" | jq -r '.[] | [.id, .path, .path_with_namespace, .visibility] | @tsv' >> "$PROJECT_FILE"
    total=$((total+len))
    printf '\r  page %d, %d projects   ' "$page" "$total"
    page=$((page+1))
  done
  printf '\n'

  if [ -s "$EXCLUDE_FILE" ]; then
    awk -F'\t' 'NR==FNR{skip[$1];next} !($2 in skip)' "$EXCLUDE_FILE" "$PROJECT_FILE" > "$WORKDIR/.f" \
      && mv "$WORKDIR/.f" "$PROJECT_FILE"
    info "exclusions applied from $EXCLUDE_FILE"
  fi

  info "$(count_rows) projects in $PROJECT_FILE"

  local dupes
  dupes=$(cut -f2 "$PROJECT_FILE" | sort | uniq -d)
  if [ -n "$dupes" ]; then
    warn "name collisions, only one of each can exist under $GITHUB_OWNER:"
    printf '      %s\n' $dupes
    warn "rename on GitLab, or add names to $EXCLUDE_FILE and rerun"
    return 1
  fi
  info "no name collisions"
}

# ---------------------------------------------------------------- B. repos

create_repos() {
  require_session || return 1; require_list || return 1
  local url total n=0 code msg priv
  url=$(gh_create_url); total=$(count_rows)
  : > "$WORKDIR/created.log"
  say "Creating GitHub repositories under $GITHUB_OWNER"
  while IFS=$'\t' read -r id path full vis; do
    case "$vis" in public) priv=false ;; *) priv=true ;; esac
    code=$(curl "${CURL_OPTS[@]}" -o "$WORKDIR/resp.json" -w '%{http_code}' -X POST \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "Content-Type: application/json" \
      "$url" \
      -d "$(jq -nc --arg n "$path" --argjson p "$priv" \
        '{name:$n,private:$p,has_issues:false,has_wiki:false}')")
    msg=$(jq -r '.message // "ok"' "$WORKDIR/resp.json" 2>/dev/null || echo "unparsed")
    logline REPO "$path $code $msg"
    printf '%s\t%s\t%s\n' "$path" "$code" "$msg" >> "$WORKDIR/created.log"
    n=$((n+1)); progress "created" "$n" "$total"
    sleep "$SLEEP_BETWEEN"
  done < "$PROJECT_FILE"
  report_log "$WORKDIR/created.log" 201 "created"
}

# ---------------------------------------------------------------- C. mirrors

create_mirrors() {
  require_session || return 1; require_list || return 1
  local total n=0 code
  total=$(count_rows)
  : > "$WORKDIR/mirrors.log"
  say "Creating push mirrors"
  while IFS=$'\t' read -r id path full vis; do
    code=$(curl "${CURL_OPTS[@]}" -o /dev/null -w '%{http_code}' -X POST \
      --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "Content-Type: application/json" \
      "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors" \
      -d "$(jq -nc --arg u "$(mirror_url "$path")" \
        '{url:$u,enabled:true,only_protected_branches:false}')")
    logline MIRR "$path $code"
    printf '%s\t%s\n' "$path" "$code" >> "$WORKDIR/mirrors.log"
    n=$((n+1)); progress "mirrored" "$n" "$total"
    sleep "$SLEEP_BETWEEN"
  done < "$PROJECT_FILE"
  report_log "$WORKDIR/mirrors.log" 201 "mirrors created"
}

# ---------------------------------------------------------------- D. sync

sync_mirrors() {
  require_session || return 1; require_list || return 1
  local total n=0 code mid
  total=$(count_rows)
  : > "$WORKDIR/sync.log"
  say "Forcing initial sync"
  while IFS=$'\t' read -r id path full vis; do
    mid=$(mirror_id_for "$id")
    if [ -z "$mid" ]; then
      printf '%s\tnomirror\n' "$path" >> "$WORKDIR/sync.log"
    else
      code=$(curl "${CURL_OPTS[@]}" -o /dev/null -w '%{http_code}' -X POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors/$mid/sync")
      logline SYNC "$path $code"
      printf '%s\t%s\n' "$path" "$code" >> "$WORKDIR/sync.log"
    fi
    n=$((n+1)); progress "synced" "$n" "$total"
    sleep "$SLEEP_BETWEEN"
  done < "$PROJECT_FILE"
  report_log "$WORKDIR/sync.log" 204 "sync requests accepted"
  info "pushes run asynchronously, and GitLab allows about one update per project every 5 minutes"
}

# ---------------------------------------------------------------- E. status

check_status() {
  require_session || return 1; require_list || return 1
  local total n=0
  total=$(count_rows)
  : > "$WORKDIR/status.log"
  say "Reading mirror status"
  while IFS=$'\t' read -r id path full vis; do
    curl "${CURL_OPTS[@]}" --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors" \
      | jq -r --arg p "$path" '.[0] // {} | [$p, (.update_status // "nomirror"), (.last_error // "none")] | @tsv' \
      >> "$WORKDIR/status.log"
    n=$((n+1)); progress "checked" "$n" "$total"
    sleep "$SLEEP_BETWEEN"
  done < "$PROJECT_FILE"

  local ok
  ok=$(awk -F'\t' '$2=="finished"' "$WORKDIR/status.log" | wc -l | tr -d ' ')
  info "finished: $ok of $total"
  rule
  awk -F'\t' '$2!="finished"{printf "  %-32s %-12s %s\n", $1, $2, substr($3,1,60)}' "$WORKDIR/status.log"
  rule
  info "symptom table: docs/90-failures.md"
}

# ---------------------------------------------------------------- F. rebuild

rebuild_mirrors() {
  require_session || return 1; require_list || return 1
  say "Deletes every existing mirror and recreates it with the current GitHub token."
  say "Content already on GitHub is not modified."
  confirm "Rebuild $(count_rows) mirrors?" || { info "cancelled"; return 0; }
  local total n=0 code mid
  total=$(count_rows)
  : > "$WORKDIR/rebuild.log"
  while IFS=$'\t' read -r id path full vis; do
    mid=$(mirror_id_for "$id")
    [ -n "$mid" ] && curl "${CURL_OPTS[@]}" -o /dev/null -X DELETE \
      --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors/$mid"
    code=$(curl "${CURL_OPTS[@]}" -o /dev/null -w '%{http_code}' -X POST \
      --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "Content-Type: application/json" \
      "https://$GITLAB_HOST/api/v4/projects/$id/remote_mirrors" \
      -d "$(jq -nc --arg u "$(mirror_url "$path")" \
        '{url:$u,enabled:true,only_protected_branches:false}')")
    logline RBLD "$path $code"
    printf '%s\t%s\n' "$path" "$code" >> "$WORKDIR/rebuild.log"
    n=$((n+1)); progress "rebuilt" "$n" "$total"
    sleep "$SLEEP_BETWEEN"
  done < "$PROJECT_FILE"
  report_log "$WORKDIR/rebuild.log" 201 "mirrors rebuilt"
  info "step 5 transfers the commits made during the outage"
}

# ---------------------------------------------------------------- G. visibility

fix_visibility() {
  require_session || return 1; require_list || return 1
  local total n=0 code priv
  total=$(count_rows)
  : > "$WORKDIR/visfix.log"
  say "Aligning GitHub visibility with GitLab"
  while IFS=$'\t' read -r id path full vis; do
    case "$vis" in public) priv=false ;; *) priv=true ;; esac
    code=$(curl "${CURL_OPTS[@]}" -o /dev/null -w '%{http_code}' -X PATCH \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "Content-Type: application/json" \
      "https://api.github.com/repos/$GITHUB_OWNER/$path" \
      -d "$(jq -nc --argjson p "$priv" '{private:$p}')")
    logline VIS "$path $code"
    printf '%s\t%s\n' "$path" "$code" >> "$WORKDIR/visfix.log"
    n=$((n+1)); progress "updated" "$n" "$total"
    sleep "$SLEEP_BETWEEN"
  done < "$PROJECT_FILE"
  report_log "$WORKDIR/visfix.log" 200 "visibility aligned"
}

# ---------------------------------------------------------------- H. verify

verify_content() {
  require_session || return 1; require_list || return 1
  local total n=0 sha
  total=$(count_rows)
  : > "$WORKDIR/verify.log"
  say "Checking for commits on GitHub"
  while IFS=$'\t' read -r id path full vis; do
    sha=$(curl "${CURL_OPTS[@]}" -H "Authorization: Bearer $GITHUB_TOKEN" \
      "https://api.github.com/repos/$GITHUB_OWNER/$path/commits?per_page=1" \
      | jq -r 'if type=="array" then (.[0].sha // "empty") else (.message // "error") end')
    logline VERF "$path $sha"
    printf '%s\t%s\n' "$path" "$sha" >> "$WORKDIR/verify.log"
    n=$((n+1)); progress "verified" "$n" "$total"
    sleep "$SLEEP_BETWEEN"
  done < "$PROJECT_FILE"
  local bad
  bad=$(awk -F'\t' 'length($2)!=40' "$WORKDIR/verify.log")
  if [ -z "$bad" ]; then
    info "all $total repositories contain commits"
  else
    warn "repositories without commits:"
    printf '%s\n' "$bad" | awk -F'\t' '{printf "      %-32s %s\n", $1, $2}'
    info "an empty GitLab source produces the same result"
  fi
}

# ---------------------------------------------------------------- I. one project

add_one() {
  require_session || return 1
  local name pid code mid gh_url priv vis
  read -r -p "Repository name: " name
  [ -n "$name" ] || { warn "no name given"; return 1; }

  pid=$(curl "${CURL_OPTS[@]}" --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects?owned=true&search=$name" \
    | jq -r --arg n "$name" '[.[] | select(.path==$n)][0].id // empty')

  if [ -z "$pid" ]; then
    warn "no GitLab project named $name"
    confirm "Create it?" || return 0
    local newvis
    read -r -p "Visibility [public/private]: " newvis
    case "$newvis" in private) newvis=private ;; *) newvis=public ;; esac
    pid=$(curl "${CURL_OPTS[@]}" -X POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      --header "Content-Type: application/json" \
      "https://$GITLAB_HOST/api/v4/projects" \
      -d "$(jq -nc --arg n "$name" --arg v "$newvis" \
        '{name:$n,path:$n,visibility:$v,initialize_with_readme:false}')" | jq -r '.id // empty')
    [ -n "$pid" ] || { warn "project creation failed"; return 1; }
    info "created GitLab project $pid"
    vis="$newvis"
  else
    vis=$(curl "${CURL_OPTS[@]}" --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      "https://$GITLAB_HOST/api/v4/projects/$pid" | jq -r .visibility)
    info "found GitLab project $pid, visibility $vis"
  fi

  case "$vis" in public) priv=false ;; *) priv=true ;; esac
  gh_url=$(gh_create_url)
  code=$(curl "${CURL_OPTS[@]}" -o "$WORKDIR/resp.json" -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" "$gh_url" \
    -d "$(jq -nc --arg n "$name" --argjson p "$priv" \
      '{name:$n,private:$p,has_issues:false,has_wiki:false}')")
  case "$code" in
    201) info "GitHub repository created" ;;
    422) info "GitHub repository exists already" ;;
    *)   warn "GitHub returned $code: $(jq -r '.message // "no message"' "$WORKDIR/resp.json")"; return 1 ;;
  esac

  mid=$(mirror_id_for "$pid")
  if [ -n "$mid" ]; then
    info "mirror exists already, id $mid"
  else
    code=$(curl "${CURL_OPTS[@]}" -o /dev/null -w '%{http_code}' -X POST \
      --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "Content-Type: application/json" \
      "https://$GITLAB_HOST/api/v4/projects/$pid/remote_mirrors" \
      -d "$(jq -nc --arg u "$(mirror_url "$name")" \
        '{url:$u,enabled:true,only_protected_branches:false}')")
    [ "$code" = "201" ] || { warn "mirror creation returned $code"; return 1; }
    info "mirror created"
    mid=$(mirror_id_for "$pid")
  fi

  curl "${CURL_OPTS[@]}" -o /dev/null -X POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects/$pid/remote_mirrors/$mid/sync"
  info "sync requested, allow up to 5 minutes"
  info "the project list no longer matches GitLab, and step 2 regenerates it"
}

# ---------------------------------------------------------------- reporting

report_log() {
  local file="$1" want="$2" label="$3" ok bad
  ok=$(awk -F'\t' -v w="$want" '$2==w' "$file" | wc -l | tr -d ' ')
  bad=$(awk -F'\t' -v w="$want" '$2!=w' "$file")
  info "$label: $ok"
  if [ -n "$bad" ]; then
    warn "failures:"
    printf '%s\n' "$bad" | awk -F'\t' '{printf "      %-32s %-6s %s\n", $1, $2, substr($3,1,50)}'
    info "resume guidance: docs/90-failures.md"
  fi
}

full_setup() {
  require_session || return 1
  build_list || return 1
  confirm "Create $(count_rows) GitHub repositories and mirrors?" || { info "cancelled"; return 0; }
  create_repos
  create_mirrors
  sync_mirrors
  info "wait a few minutes, then run step 6"
}

# ---------------------------------------------------------------- wizard mode

WIZ_TOTAL=6

wiz_title() {
  case "$1" in
    1) printf 'Session, tokens and target' ;;
    2) printf 'Build project list' ;;
    3) printf 'Create GitHub repositories' ;;
    4) printf 'Create mirrors' ;;
    5) printf 'Force sync' ;;
    6) printf 'Mirror status' ;;
  esac
}

wiz_doc() {
  case "$1" in
    1) printf 'docs/03-session.md' ;;
    2) printf 'docs/10-project-list.md' ;;
    3) printf 'docs/11-create-repos.md' ;;
    4) printf 'docs/12-create-mirrors.md' ;;
    5) printf 'docs/13-sync.md' ;;
    6) printf 'docs/20-status.md' ;;
  esac
}

# Page heading and instruction, shown above the input on each page.
wiz_heading() {
  case "$1" in
    1) printf 'Credentials' ;;
    2) printf 'Projects to mirror' ;;
    3) printf 'Repositories on GitHub' ;;
    4) printf 'Mirror configuration' ;;
    5) printf 'First transfer' ;;
    6) printf 'Results' ;;
  esac
}

wiz_brief() {
  case "$1" in
    1) say ' Enter a GitLab token with api scope and a GitHub token with repo scope, then'
       say ' choose where the copies go. Both tokens are kept in memory only.' ;;
    2) say ' Lists every project your GitLab token can see, and checks for names that would'
       say ' collide on GitHub. Nothing is changed.' ;;
    3) say ' Creates one GitHub repository per listed project, matching its GitLab'
       say ' visibility. Existing repositories are not modified.' ;;
    4) say ' Points each GitLab project at its GitHub counterpart.'
       say ' After this, each commit you push to GitLab is transferred to GitHub'
       say ' automatically.' ;;
    5) say ' Sends existing history once per project.'
       say ' A new mirror otherwise waits for your next commit.' ;;
    6) say ' Reports the outcome of every mirror, with a reason for anything unfinished.' ;;
  esac
}

# Shown after the step finishes, reading real state.
wiz_result() {
  case "$1" in
    1) if [ -n "$GITHUB_OWNER" ]; then
         info "session active: $GITHUB_OWNER on $GITLAB_HOST, selector $GITLAB_SELECTOR"
       else
         info "no session"
       fi ;;
    2) info "$(state_of list)" ;;
    3) info "$(state_of log created.log 201)" ;;
    4) info "$(state_of log mirrors.log 201)" ;;
    5) info "$(state_of log sync.log 204)"
       info "GitLab allows about one mirror update per project every 5 minutes" ;;
    6) info "$(state_of status status.log)" ;;
  esac
}

# Shown after the step, describing the next one.
wiz_ahead() {
  local n=$(( $1 + 1 ))
  if [ "$n" -gt "$WIZ_TOTAL" ]; then
    say '   Setup is complete. Mirrors run on GitLab infrastructure from this point,'
    say '   and each push to GitLab is transferred to GitHub automatically.'
    say ''
    say '   Later on:'
    say '     step 7   confirm the commits were transferred to GitHub'
    say '     step 8   rebuild mirrors after replacing the GitHub token'
    say '     step 10  add a single project without rebuilding the list'
    return
  fi
  printf '   Step %d of %d: %s\n' "$n" "$WIZ_TOTAL" "$(wiz_title "$n")"
  say ''
  wiz_brief "$n"
}

wiz_run() {
  case "$1" in
    1) load_session ;;
    2) build_list ;;
    3) create_repos ;;
    4) create_mirrors ;;
    5) sync_mirrors ;;
    6) check_status ;;
  esac
}

wizard_mode() {
  local step=1 choice rc
  cls
  rule
  say ' Guided setup'
  rule
  say ' Sets up one-way mirroring: every GitLab project gets a matching GitHub'
  say ' repository, and GitLab pushes to it on every commit.'
  say ' You keep working on GitLab. GitHub stores a copy that is updated automatically.'
  say ''
  say ' Steps 1 and 2 make no changes. Steps 3 to 5 create repositories and mirrors.'
  say ' Exiting at any point preserves the completed steps.'
  rule
  read -r -p ' Enter to begin, Q to return to the menu: ' choice
  case "$choice" in q|Q) return 0 ;; esac

  while [ "$step" -le "$WIZ_TOTAL" ]; do
    cls
    rule
    printf ' Guided setup%*sStep %d of %d\n' 38 "" "$step" "$WIZ_TOTAL"
    rule
    echo
    printf ' %s\n' "$(wiz_heading "$step")"
    say ''
    wiz_brief "$step"
    say ''
    rc=0
    WIZ_MSGS=""
    WIZ_CAPTURE=1
    logline STEP "$step start: $(wiz_title "$step")"
    wiz_run "$step" || rc=$?
    WIZ_CAPTURE=0
    logline STEP "$step exit=$rc"

    echo
    cls
    rule
    printf ' Guided setup%*sStep %d of %d\n' 38 "" "$step" "$WIZ_TOTAL"
    rule
    echo
    if [ "$rc" -ne 0 ]; then
      printf ' %s: incomplete\n' "$(wiz_heading "$step")"
      say ''
      [ -n "$WIZ_MSGS" ] && printf '%s' "$WIZ_MSGS" && say ''
      wiz_result "$step"
      say ''
      say ' Clear the cause, then repeat this page.'
      say ' Failure messages are listed in docs/90-failures.md.'
    else
      printf ' %s: done\n' "$(wiz_heading "$step")"
      say ''
      wiz_result "$step"
      say ''
      wiz_ahead "$step"
    fi
    rule
    if [ "$rc" -ne 0 ]; then
      say '  Enter Repeat    C Continue anyway    B Back    M Cancel'
    elif [ "$step" -lt "$WIZ_TOTAL" ]; then
      say '  Enter Next    B Back    R Repeat    M Cancel'
    else
      say '  Enter Finish    B Back    R Repeat    M Cancel'
    fi
    rule
    read -r -p ' Choice: ' choice
    logline NAV "step=$step rc=$rc key=$choice"
    if [ "$rc" -ne 0 ]; then
      case "$choice" in
        c|C) step=$((step+1)) ;;
        b|B) [ "$step" -gt 1 ] && step=$((step-1)) ;;
        m|M) return 0 ;;
        *)   : ;;
      esac
      continue
    fi
    case "$choice" in
      r|R) continue ;;
      b|B) [ "$step" -gt 1 ] && step=$((step-1)); continue ;;
      m|M) return 0 ;;
      *)   step=$((step+1)) ;;
    esac
  done

  echo
  cls
  rule
  say ' Guided setup finished'
  rule
  say ' State'
  item "" "Project list"          "$(state_of list)"
  item "" "GitHub repositories"   "$(state_of log created.log 201)"
  item "" "Mirrors"               "$(state_of log mirrors.log 201)"
  item "" "Sync requests"         "$(state_of log sync.log 204)"
  item "" "Mirror status"         "$(state_of status status.log)"
  say ''
  say ' Failed items are listed in the log files under:'
  say "   $WORKDIR"
  say ' Failure messages are explained in docs/90-failures.md.'
  rule
  read -r -p ' Enter to return to the menu: ' choice
}

# ---------------------------------------------------------------- menu

# Per-step state, drawn in the right-hand column of the menu.
state_of() {
  local f="$WORKDIR/${2-}" ok
  case "$1" in
    session)
      [ -n "$GITLAB_TOKEN" ] && [ -n "$GITHUB_TOKEN" ] && printf '%s' "$GITHUB_OWNER" || printf 'not loaded'
      ;;
    list)
      [ -s "$PROJECT_FILE" ] && printf '%s projects' "$(count_rows)" || printf 'empty'
      ;;
    log)
      [ -s "$f" ] || { printf 'not run'; return; }
      ok=$(awk -F'\t' -v w="${3-}" '$2==w' "$f" | wc -l | tr -d ' ')
      printf '%s of %s ok' "$ok" "$(wc -l < "$f" | tr -d ' ')"
      ;;
    status)
      [ -s "$f" ] || { printf 'not run'; return; }
      ok=$(awk -F'\t' '$2=="finished"' "$f" | wc -l | tr -d ' ')
      printf '%s of %s finished' "$ok" "$(wc -l < "$f" | tr -d ' ')"
      ;;
    verify)
      [ -s "$f" ] || { printf 'not run'; return; }
      ok=$(awk -F'\t' 'length($2)==40' "$f" | wc -l | tr -d ' ')
      printf '%s of %s populated' "$ok" "$(wc -l < "$f" | tr -d ' ')"
      ;;
  esac
}

item() { printf '  %-3s %-38s %s\n' "$1" "$2" "$3"; }

menu() {
  cls
  rule
  printf ' %-43s %s\n' "GitLab to GitHub push mirroring" "${GITLAB_HOST:-no host set}"
  rule
  say ' Setup'
  item 1  "Session, tokens and target"        "$(state_of session)"
  item 2  "Build project list"                "$(state_of list)"
  item 3  "Create GitHub repositories"        "$(state_of log created.log 201)"
  item 4  "Create mirrors"                    "$(state_of log mirrors.log 201)"
  item 5  "Force sync"                        "$(state_of log sync.log 204)"
  say ' Check'
  item 6  "Mirror status"                     "$(state_of status status.log)"
  item 7  "Content on GitHub"                 "$(state_of verify verify.log)"
  say ' Repair'
  item 8  "Rebuild mirrors after token change" "$(state_of log rebuild.log 201)"
  item 9  "Align repository visibility"       "$(state_of log visfix.log 200)"
  say ' Other'
  item 10 "Add one project" ""
  item 11 "Run steps 2 to 5 unattended" ""
  item 12 "Guided setup, one step per screen" ""
  rule
  printf '  1-12 Select    H Help    Q Quit\n'
  rule
}

show_help() {
  cls
  rule
  say ' Help'
  rule
  say ' For a first-time setup, run steps 2 to 5 in order, step 11 without prompts, or'
  say ' step 12 one page at a time.'
  say ' Steps 6 and 7 only read data, and can be repeated at any time.'
  say ' Steps 8 and 9 rewrite existing configuration and ask for confirmation.'
  say ''
  say ' Each step has a page under docs/:'
  say '   2  docs/10-project-list.md      6  docs/20-status.md'
  say '   3  docs/11-create-repos.md      7  docs/23-verify.md'
  say '   4  docs/12-create-mirrors.md    8  docs/21-rebuild.md'
  say '   5  docs/13-sync.md              9  docs/22-visibility.md'
  say '   10 docs/30-add-one.md'
  say ''
  say ' Failure messages are listed in docs/90-failures.md.'
  say ' Logs from the last run are in:'
  say "   $WORKDIR"
  rule
}

action_title() {
  case "$1" in
    1)  printf 'Session, tokens and target' ;;
    2)  printf 'Build project list' ;;
    3)  printf 'Create GitHub repositories' ;;
    4)  printf 'Create mirrors' ;;
    5)  printf 'Force sync' ;;
    6)  printf 'Mirror status' ;;
    7)  printf 'Content on GitHub' ;;
    8)  printf 'Rebuild mirrors' ;;
    9)  printf 'Align repository visibility' ;;
    10) printf 'Add one project' ;;
    11) printf 'Steps 2 to 5, unattended' ;;
  esac
}

main() {
  check_deps
  mkdir -p "$WORKDIR"
  logline START "pid $$ cwd $PWD"
  trap 'logline END "session closed"' EXIT
  local choice
  while :; do
    menu
    read -r -p ' Choice: ' choice
    logline MENU "choice=$choice"
    case "$choice" in
      1|2|3|4|5|6|7|8|9|10|11)
        cls
        rule
        printf ' %s\n' "$(action_title "$choice")"
        rule
        echo
        ;;
    esac
    case "$choice" in
      1)  load_session ;;
      2)  build_list ;;
      3)  create_repos ;;
      4)  create_mirrors ;;
      5)  sync_mirrors ;;
      6)  check_status ;;
      7)  verify_content ;;
      8)  rebuild_mirrors ;;
      9)  fix_visibility ;;
      10) add_one ;;
      11) full_setup ;;
      12) wizard_mode ;;
      h|H|help|\?) show_help ;;
      q|Q|quit|exit) break ;;
      "") : ;;
      *)  warn "unknown choice: $choice" ;;
    esac
    case "$choice" in
      12|q|Q|quit|exit|"") : ;;
      *)  echo; rule; read -r -p ' Enter to return to the menu: ' choice ;;
    esac
  done
}

main "$@"
