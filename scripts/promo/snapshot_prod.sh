#!/usr/bin/env bash
# Take a fresh snapshot of the production database and restore it into a
# SEPARATE local database (`mehungry_promo` by default) for recording the promo
# video with `mix promo.record`. The everyday dev DB (`mehungry_server_dev`) is
# never touched.
#
# The prod connection string is read from (first hit wins):
#   1. $PROD_DATABASE_URL
#   2. the file at $PROD_DATABASE_URL_FILE (default ~/.config/mehungry/prod_db_url)
# Use the Supabase *session pooler* URL (…pooler.supabase.com:5432): the direct
# db.<ref>.supabase.co host is IPv6-only and this machine has no IPv6 egress.
#
# Read-only against prod (pg_dump only SELECTs). Covers the `public` schema;
# the DATA of these is never copied (see SKIP_DATA below):
#   oban_jobs / oban_peers   — never replay prod jobs locally (social publishing!)
#   users_tokens, user_devices, professional_google_accounts — live credentials
#   research/literature corpus (*_responses, study_*, *_mined_facts, …) — bulky,
#     never shown in the consumer flow being filmed
# See docs/growth/promo_video.md.
#
# Usage:  scripts/promo/snapshot_prod.sh [target_db]
set -euo pipefail

TARGET_DB="${1:-mehungry_promo}"
LOCAL_PG=(-h "${LOCAL_PGHOST:-localhost}" -p "${LOCAL_PGPORT:-5432}" -U "${LOCAL_PGUSER:-postgres}")
export PGPASSWORD="${LOCAL_PGPASSWORD:-postgres}"

if [[ "$TARGET_DB" == "mehungry_server_dev" || "$TARGET_DB" == "mehungry_server_test" ]]; then
  echo "Refusing to overwrite $TARGET_DB — pick a dedicated promo database." >&2
  exit 1
fi

URL="${PROD_DATABASE_URL:-}"
URL_FILE="${PROD_DATABASE_URL_FILE:-$HOME/.config/mehungry/prod_db_url}"
if [[ -z "$URL" && -r "$URL_FILE" ]]; then
  URL="$(tr -d '[:space:]' < "$URL_FILE")"
fi
if [[ -z "$URL" ]]; then
  cat >&2 <<EOF
No prod connection string. Either export PROD_DATABASE_URL, or put it in
$URL_FILE (chmod 600). Use the Supabase session-pooler URL.
EOF
  exit 1
fi

# Split the URL into libpq env vars so the password never appears in a process
# argv (visible to `ps`); /proc/<pid>/environ is owner-only.
eval "$(python3 -I - "$URL" <<'PY'
import sys, shlex
from urllib.parse import urlsplit, unquote
u = urlsplit(sys.argv[1])
for k, v in {"P_HOST": u.hostname, "P_PORT": str(u.port or 5432), "P_USER": unquote(u.username or ""),
             "P_PASS": unquote(u.password or ""), "P_DB": (u.path or "/postgres").lstrip("/")}.items():
    print(f"{k}={shlex.quote(v)}")
PY
)"
unset URL
# Keepalives: the Supabase pooler has been seen to stall mid-COPY.
prod() {
  env PGHOST="$P_HOST" PGPORT="$P_PORT" PGUSER="$P_USER" PGPASSWORD="$P_PASS" PGDATABASE="$P_DB" \
      PGSSLMODE=require PGCONNECT_TIMEOUT=15 \
      PGOPTIONS="-c statement_timeout=0" "$@"
}

# Newest client tools on the box — pg_dump must be >= the server's major version.
PGBIN="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)"
echo "Using client tools from $PGBIN"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mehungry_promo.XXXXXX")"
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

echo "→ Prod server: $(prod "$PGBIN/psql" -Atc 'show server_version')"

# Where prod keeps its extensions (Supabase usually puts them in `extensions`),
# so the restored column types (e.g. extensions.vector) resolve locally.
EXTS="$(prod "$PGBIN/psql" -AtF' ' -c \
  "select e.extname, n.nspname from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname in ('vector','citext','pg_trgm','unaccent','uuid-ossp','pgcrypto','postgis')")"
echo "→ Prod extensions: $(echo "$EXTS" | tr '\n' ';')"

KEEPALIVE="keepalives=1 keepalives_idle=30 keepalives_interval=10 keepalives_count=6"

# Tables whose DATA we never copy: live credentials / prod job queues (see the
# header), plus the bulky research/literature corpus the consumer flow never
# shows. Shell globs against the bare table name.
SKIP_DATA=(oban_jobs oban_peers users_tokens user_devices professional_google_accounts
           visits '*_responses' '*_mined_facts' 'study_*' scientific_studies
           'literature_*' 'pubtator_*' 'research_*' '*_fact_mining_runs')
skip_data() { local t="$1" g; for g in "${SKIP_DATA[@]}"; do [[ "$t" == $g ]] && return 0; done; return 1; }

# One long dump through the Supabase pooler gets its connection dropped
# mid-COPY, so: the schema once, then every table's data in its own short
# connection, retried.
echo "→ Dumping prod schema (read-only)…"
mkdir -p "$WORK/data"
prod timeout 600 "$PGBIN/pg_dump" --dbname="$KEEPALIVE" --schema=public --schema-only \
  --format=custom --no-owner --no-privileges --no-comments --file="$WORK/schema.dump"

mapfile -t ROWS < <(prod "$PGBIN/psql" -AtF' ' -c \
  "select c.relname, pg_total_relation_size(c.oid) from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p') order by 2 desc")

# Each pg_dump spends ~20s on catalog queries through the pooler, so batch the
# small tables (40 per connection) and give each big one its own connection.
# Tables above ~50MB can't survive one COPY through the pooler at all — those
# are pulled as id-range CSV chunks with \copy instead (see below).
BIG=(); SMALL=(); HUGE=()
for row in "${ROWS[@]}"; do
  t="${row% *}"; size="${row##* }"
  skip_data "$t" && continue
  if (( size > 50000000 )); then HUGE+=("$t")
  elif (( size > 2000000 )); then BIG+=("$t")
  else SMALL+=("$t"); fi
done
GROUPS_=()
for t in "${BIG[@]}"; do GROUPS_+=("$t"); done
for ((i = 0; i < ${#SMALL[@]}; i += 40)); do GROUPS_+=("${SMALL[*]:i:40}"); done

echo "→ Dumping data: ${#BIG[@]} large tables + ${#SMALL[@]} small ones in ${#GROUPS_[@]} connections…"
FAILED=()
n=0
for group in "${GROUPS_[@]}"; do
  n=$((n + 1))
  args=(); for t in $group; do args+=(--table="public.\"$t\""); done
  ok=0
  for attempt in 1 2 3 4; do
    if prod timeout 900 "$PGBIN/pg_dump" --dbname="$KEEPALIVE" --data-only --format=custom \
         --no-owner --no-privileges "${args[@]}" --file="$WORK/data/$n.dump" 2>"$WORK/err"; then
      ok=1; break
    fi
    echo "   batch $n: attempt $attempt failed ($(head -1 "$WORK/err" | cut -c1-90)) — retrying"
    sleep $((attempt * 3))
  done
  [[ $ok == 1 ]] && echo "   batch $n/${#GROUPS_[@]} ok (${group:0:60})" || FAILED+=("$group")
done
# Chunked pull for huge tables: one short connection per 250k-id range.
CHUNK=250000
for t in "${HUGE[@]}"; do
  read -r lo hi < <(prod "$PGBIN/psql" -AtF' ' -c "select coalesce(min(id),0), coalesce(max(id),0) from public.\"$t\"")
  echo "→ Chunked copy of $t (ids $lo..$hi)…"
  mkdir -p "$WORK/chunks/$t"
  for ((a = lo; a <= hi; a += CHUNK)); do
    b=$((a + CHUNK))
    ok=0
    for attempt in 1 2 3 4 5; do
      if prod timeout 600 "$PGBIN/psql" -q -v ON_ERROR_STOP=1 \
           -c "\\copy (select * from public.\"$t\" where id >= $a and id < $b) to '$WORK/chunks/$t/$a.csv' with (format csv)" \
           2>"$WORK/err"; then ok=1; break; fi
      echo "   $t [$a,$b): attempt $attempt failed ($(head -1 "$WORK/err" | cut -c1-80))"
      sleep $((attempt * 3))
    done
    [[ $ok == 1 ]] || FAILED+=("$t[$a,$b)")
  done
  echo "   $t: $(cat "$WORK/chunks/$t"/*.csv | wc -l) rows"
done

if (( ${#FAILED[@]} )); then
  echo "!! Could not dump: ${FAILED[*]}" >&2
  exit 1
fi
echo "   dumped: $(du -sh "$WORK" | cut -f1)"

echo "→ Recreating local database $TARGET_DB…"
"$PGBIN/psql" "${LOCAL_PG[@]}" -v ON_ERROR_STOP=1 -q -d postgres \
  -c "drop database if exists \"$TARGET_DB\" with (force)" \
  -c "create database \"$TARGET_DB\""

SEARCH_PATH="public"
while read -r ext schema; do
  [[ -z "${ext:-}" ]] && continue
  "$PGBIN/psql" "${LOCAL_PG[@]}" -v ON_ERROR_STOP=1 -q -d "$TARGET_DB" \
    -c "create schema if not exists \"$schema\"" \
    -c "create extension if not exists \"$ext\" with schema \"$schema\""
  [[ ",$SEARCH_PATH," == *",$schema,"* ]] || SEARCH_PATH="$SEARCH_PATH, $schema"
done <<< "$EXTS"
"$PGBIN/psql" "${LOCAL_PG[@]}" -q -d postgres \
  -c "alter database \"$TARGET_DB\" set search_path = $SEARCH_PATH"

# Render each archive to SQL with the new pg_restore, drop settings an older
# local server doesn't know (PG17+ transaction_timeout), load with local psql.
load() {
  "$PGBIN/pg_restore" --no-owner --no-privileges -f - "$@" \
    | sed -e '/^SET transaction_timeout/d' \
    | "$PGBIN/psql" "${LOCAL_PG[@]}" -q -d "$TARGET_DB" -v ON_ERROR_STOP=0 \
        2>> "$WORK/restore_errors.log" >/dev/null || true
}

echo "→ Restoring schema, data, then indexes/constraints…"
: > "$WORK/restore_errors.log"
load --section=pre-data "$WORK/schema.dump"
for f in "$WORK"/data/*.dump; do load "$f"; done
for t in "${HUGE[@]}"; do
  for f in "$WORK/chunks/$t"/*.csv; do
    "$PGBIN/psql" "${LOCAL_PG[@]}" -q -d "$TARGET_DB" \
      -c "\\copy public.\"$t\" from '$f' with (format csv)" 2>> "$WORK/restore_errors.log"
  done
done
load --section=post-data "$WORK/schema.dump"

# Per-table data dumps don't carry sequence positions — bump every serial past
# its table's max id so the app's inserts don't collide.
"$PGBIN/psql" "${LOCAL_PG[@]}" -q -d "$TARGET_DB" <<'SQL'
do $$
declare r record; m bigint;
begin
  for r in
    select s.relname as seq, t.relname as tbl, a.attname as col
    from pg_class s
    join pg_depend d on d.objid = s.oid and d.deptype in ('a','i')
    join pg_class t on t.oid = d.refobjid
    join pg_attribute a on a.attrelid = t.oid and a.attnum = d.refobjsubid
    join pg_namespace n on n.oid = s.relnamespace
    where s.relkind = 'S' and n.nspname = 'public'
  loop
    execute format('select max(%I) from public.%I', r.col, r.tbl) into m;
    if m is not null then perform setval(format('public.%I', r.seq), m); end if;
  end loop;
end $$;
SQL

# Materialized views come over as empty shells (data dumps skip them); an
# unpopulated one raises on read (recipe_search backs the planner's FTS fallback).
"$PGBIN/psql" "${LOCAL_PG[@]}" -q -d "$TARGET_DB" <<'SQL'
do $$
declare v record;
begin
  for v in select schemaname, matviewname from pg_matviews where schemaname = 'public' loop
    execute format('refresh materialized view %I.%I', v.schemaname, v.matviewname);
  end loop;
end $$;
SQL

ERRS=$(grep -c 'ERROR' "$WORK/restore_errors.log" || true)
if [[ "$ERRS" != "0" ]]; then
  echo "   $ERRS restore errors (usually Supabase-only roles/policies — harmless). Distinct:"
  grep 'ERROR' "$WORK/restore_errors.log" | sort | uniq -c | sort -rn | head -10
fi

echo "→ Sanitizing (no prod jobs, no live sessions)…"
"$PGBIN/psql" "${LOCAL_PG[@]}" -q -d "$TARGET_DB" <<'SQL'
truncate table oban_jobs;
truncate table oban_peers;
SQL

echo "→ Sanity check:"
"$PGBIN/psql" "${LOCAL_PG[@]}" -d "$TARGET_DB" -c "
  select (select count(*) from users) as users,
         (select count(*) from recipes) as recipes,
         (select count(*) from recipes where image_url is not null) as recipes_with_photo,
         (select count(*) from ingredients) as ingredients,
         (select max(version) from schema_migrations) as last_migration"

echo "Done. Record with:  mix promo.record   (uses $TARGET_DB)"
