#!/usr/bin/env bash
#
# gcp-assess.sh · CrewNexa GCP Readiness Snapshot
#
# A READ-ONLY assessment of a Google Cloud project.
# Only `gcloud ... list/describe/get-iam-policy` calls are made.
# Nothing is created, modified, enabled, or deleted.
#
# Usage:   ./gcp-assess.sh PROJECT_ID
# Needs:   gcloud CLI, authenticated identity with Viewer on the project.
# Runs anywhere gcloud runs; Cloud Shell is the zero-setup option.
# Note: on macOS the key-age check (2) degrades gracefully to age 0.
#
set -uo pipefail

# ---------- formatting ----------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[0;33m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
  RED=""; GRN=""; YLW=""; BLD=""; RST=""
fi

PASS_N=0; WARN_N=0; FAIL_N=0

pass() { printf "  %s[ OK ]%s %s\n"   "$GRN" "$RST" "$1"; PASS_N=$((PASS_N+1)); }
warn() { printf "  %s[WARN]%s %s\n"   "$YLW" "$RST" "$1"; WARN_N=$((WARN_N+1)); }
fail() { printf "  %s[FAIL]%s %s\n"   "$RED" "$RST" "$1"; FAIL_N=$((FAIL_N+1)); }
info() { printf "  %s\n" "$1"; }
section() { printf "\n%s%s%s\n" "$BLD" "$1" "$RST"; }

# ---------- preflight ------------------------------------------------------
PROJECT="${1:-}"
if [[ -z "$PROJECT" ]]; then
  echo "Usage: $0 PROJECT_ID" >&2; exit 1
fi
if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install" >&2; exit 1
fi
if ! gcloud projects describe "$PROJECT" --format="value(projectId)" >/dev/null 2>&1; then
  echo "Cannot read project '$PROJECT'. Check the ID and your permissions (Viewer is enough)." >&2; exit 1
fi

printf "%sGCP Readiness Snapshot%s · project: %s · %s\n" \
  "$BLD" "$RST" "$PROJECT" "$(date -u +'%Y-%m-%d %H:%MZ')"
printf "Read-only run. No resources will be changed.\n"

IAM_POLICY="$(gcloud projects get-iam-policy "$PROJECT" --format=json 2>/dev/null || echo '{}')"

# ---------- 1 · primitive IAM roles ---------------------------------------
section "1 · IAM: primitive roles (owner / editor)"
PRIM="$(echo "$IAM_POLICY" | python3 -c '
import json,sys
p=json.load(sys.stdin)
out=[]
for b in p.get("bindings",[]):
    if b.get("role") in ("roles/owner","roles/editor"):
        for m in b.get("members",[]):
            out.append(b["role"].split("/")[1] + ": " + m)
print("\n".join(out))' 2>/dev/null || true)"
if [[ -z "$PRIM" ]]; then
  pass "No owner/editor bindings found. Least privilege looks respected."
else
  COUNT="$(echo "$PRIM" | grep -c . || true)"
  fail "$COUNT principal(s) hold broad primitive roles:"
  echo "$PRIM" | sed 's/^/         /'
  info "→ Replace with granular predefined roles or IAM conditions."
fi

# ---------- 2 · user-managed service account keys --------------------------
section "2 · IAM: user-managed service account keys"
OLD_KEYS=0; TOTAL_KEYS=0
while IFS= read -r SA; do
  [[ -z "$SA" ]] && continue
  while IFS=$'\t' read -r KEY CREATED; do
    [[ -z "$KEY" ]] && continue
    TOTAL_KEYS=$((TOTAL_KEYS+1))
    if [[ -n "$CREATED" ]]; then
      AGE_DAYS=$(( ( $(date -u +%s) - $(date -u -d "$CREATED" +%s 2>/dev/null || echo "$(date -u +%s)") ) / 86400 ))
      if (( AGE_DAYS > 90 )); then
        OLD_KEYS=$((OLD_KEYS+1))
        warn "Key on ${SA} is ${AGE_DAYS} days old."
      fi
    fi
  done < <(gcloud iam service-accounts keys list --iam-account="$SA" \
            --managed-by=user --format="value(name,validAfterTime)" 2>/dev/null)
done < <(gcloud iam service-accounts list --project="$PROJECT" --format="value(email)" 2>/dev/null)
if (( TOTAL_KEYS == 0 )); then
  pass "No user-managed service account keys. Workload Identity or ADC in use."
elif (( OLD_KEYS == 0 )); then
  warn "$TOTAL_KEYS user-managed key(s) exist. Prefer Workload Identity; rotate on schedule."
else
  fail "$OLD_KEYS of $TOTAL_KEYS user-managed key(s) are older than 90 days. Rotate or retire."
fi

# ---------- 3 · default compute service account ----------------------------
section "3 · IAM: default compute service account"
DEFAULT_SA="$(gcloud iam service-accounts list --project="$PROJECT" \
  --filter="email:compute@developer.gserviceaccount.com" --format="value(email)" 2>/dev/null || true)"
if [[ -z "$DEFAULT_SA" ]]; then
  pass "Default compute service account not present."
else
  USED="$(gcloud compute instances list --project="$PROJECT" \
    --filter="serviceAccounts.email=${DEFAULT_SA}" --format="value(name)" 2>/dev/null | head -5 || true)"
  if [[ -z "$USED" ]]; then
    pass "Default compute SA exists but no instances use it."
  else
    fail "Instances run as the default compute SA (broad permissions by design):"
    echo "$USED" | sed 's/^/         /'
    info "→ Create minimal per-workload service accounts."
  fi
fi

# ---------- 4 · firewall exposure ------------------------------------------
section "4 · Network: firewall rules open to the internet"
OPEN_RULES="$(gcloud compute firewall-rules list --project="$PROJECT" \
  --filter="direction=INGRESS AND disabled=false AND sourceRanges:0.0.0.0/0" \
  --format="value(name,allowed[].map().firewall_rule().list())" 2>/dev/null || true)"
if [[ -z "$OPEN_RULES" ]]; then
  pass "No enabled ingress rules open to 0.0.0.0/0."
else
  CRIT=0
  while IFS=$'\t' read -r NAME ALLOWED; do
    [[ -z "$NAME" ]] && continue
    if echo "$ALLOWED" | grep -qiE '(:22(,|$)|:3389(,|$)|all)'; then
      fail "Rule '$NAME' exposes SSH/RDP or all ports to the internet ($ALLOWED)."
      CRIT=$((CRIT+1))
    else
      warn "Rule '$NAME' allows $ALLOWED from 0.0.0.0/0. Confirm it is intentional (e.g. HTTPS LB)."
    fi
  done <<< "$OPEN_RULES"
  info "→ Restrict with IAP TCP forwarding or source IP allowlists."
fi

# ---------- 5 · public buckets ---------------------------------------------
section "5 · Storage: publicly accessible buckets"
PUB=0
while IFS= read -r B; do
  [[ -z "$B" ]] && continue
  POL="$(gcloud storage buckets get-iam-policy "$B" --format=json 2>/dev/null || echo '{}')"
  if echo "$POL" | grep -qE '"(allUsers|allAuthenticatedUsers)"'; then
    fail "Bucket $B is bound to allUsers/allAuthenticatedUsers."
    PUB=$((PUB+1))
  fi
done < <(gcloud storage buckets list --project="$PROJECT" --format="value(storage_url)" 2>/dev/null)
(( PUB == 0 )) && pass "No buckets grant public access."

# ---------- 6 · uniform bucket-level access ---------------------------------
section "6 · Storage: uniform bucket-level access"
NON_UNIFORM="$(gcloud storage buckets list --project="$PROJECT" \
  --format="value(storage_url,uniform_bucket_level_access)" 2>/dev/null \
  | awk -F'\t' '$2 != "True" && $1 != "" {print $1}' || true)"
if [[ -z "$NON_UNIFORM" ]]; then
  pass "All buckets enforce uniform bucket-level access."
else
  warn "Buckets with per-object ACLs (drift risk):"
  echo "$NON_UNIFORM" | sed 's/^/         /'
fi

# ---------- 7 · GKE posture --------------------------------------------------
section "7 · GKE: cluster posture"
CLUSTERS="$(gcloud container clusters list --project="$PROJECT" \
  --format="value(name,location)" 2>/dev/null || true)"
if [[ -z "$CLUSTERS" ]]; then
  info "No GKE clusters in this project (skipped)."
else
  while IFS=$'\t' read -r CNAME CLOC; do
    [[ -z "$CNAME" ]] && continue
    CJSON="$(gcloud container clusters describe "$CNAME" --location="$CLOC" \
      --project="$PROJECT" --format=json 2>/dev/null || echo '{}')"
    PRIV="$(echo "$CJSON"    | python3 -c 'import json,sys;print(json.load(sys.stdin).get("privateClusterConfig",{}).get("enablePrivateNodes",False))' 2>/dev/null)"
    WI="$(echo "$CJSON"      | python3 -c 'import json,sys;print(bool(json.load(sys.stdin).get("workloadIdentityConfig",{}).get("workloadPool")))' 2>/dev/null)"
    CHANNEL="$(echo "$CJSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("releaseChannel",{}).get("channel","UNSPECIFIED"))' 2>/dev/null)"
    [[ "$PRIV" == "True" ]]  && pass "[$CNAME] private nodes enabled." \
                             || fail "[$CNAME] nodes have public IPs. Move to a private cluster."
    [[ "$WI" == "True" ]]    && pass "[$CNAME] Workload Identity enabled." \
                             || fail "[$CNAME] Workload Identity disabled. Pods likely rely on node SA or keys."
    [[ "$CHANNEL" != "UNSPECIFIED" ]] && pass "[$CNAME] release channel: $CHANNEL." \
                             || warn "[$CNAME] no release channel. Upgrades are manual and drift-prone."
  done <<< "$CLUSTERS"
fi

# ---------- 8 · VMs with public IPs -----------------------------------------
section "8 · Compute: instances with external IPs"
PUB_VMS="$(gcloud compute instances list --project="$PROJECT" \
  --filter="networkInterfaces.accessConfigs[0].natIP:*" --format="value(name)" 2>/dev/null || true)"
if [[ -z "$PUB_VMS" ]]; then
  pass "No VM exposes a public IP."
else
  COUNT="$(echo "$PUB_VMS" | grep -c . || true)"
  warn "$COUNT VM(s) have external IPs:"
  echo "$PUB_VMS" | head -10 | sed 's/^/         /'
  info "→ Prefer internal IPs + IAP or a load balancer in front."
fi

# ---------- 9 · OS Login ------------------------------------------------------
section "9 · Compute: OS Login at project level"
OSL="$(gcloud compute project-info describe --project="$PROJECT" --format=json 2>/dev/null \
  | python3 -c '
import json,sys
meta=json.load(sys.stdin).get("commonInstanceMetadata",{}).get("items",[])
print(next((i.get("value","") for i in meta if i.get("key")=="enable-oslogin"),""))' 2>/dev/null || true)"
if [[ "${OSL,,}" == "true" ]]; then
  pass "OS Login enforced project-wide. SSH access is IAM-governed and audited."
else
  warn "OS Login not enforced at project level. SSH keys may be unmanaged per-instance."
fi

# ---------- 10 · unattached disks ---------------------------------------------
section "10 · Cost: unattached persistent disks"
ORPHANS="$(gcloud compute disks list --project="$PROJECT" \
  --filter="-users:*" --format="value(name,sizeGb)" 2>/dev/null || true)"
if [[ -z "$ORPHANS" ]]; then
  pass "No unattached disks. No silent storage spend."
else
  TOTAL_GB="$(echo "$ORPHANS" | awk -F'\t' '{s+=$2} END {print s+0}')"
  warn "Unattached disks found (~${TOTAL_GB} GB billed monthly for nothing):"
  echo "$ORPHANS" | sed 's/^/         /'
fi

# ---------- 11 · idle static IPs -----------------------------------------------
section "11 · Cost: reserved but unused static IPs"
IDLE_IPS="$(gcloud compute addresses list --project="$PROJECT" \
  --filter="status=RESERVED" --format="value(name,address)" 2>/dev/null || true)"
if [[ -z "$IDLE_IPS" ]]; then
  pass "No idle reserved static IPs."
else
  warn "Reserved IPs not attached to anything (billed hourly):"
  echo "$IDLE_IPS" | sed 's/^/         /'
fi

# ---------- 12 · observability APIs --------------------------------------------
section "12 · Observability: Logging & Monitoring APIs"
ENABLED="$(gcloud services list --enabled --project="$PROJECT" \
  --filter="name:(logging.googleapis.com OR monitoring.googleapis.com)" \
  --format="value(config.name)" 2>/dev/null || true)"
echo "$ENABLED" | grep -q "logging.googleapis.com"    && pass "Cloud Logging API enabled." \
                                                       || fail "Cloud Logging API disabled."
echo "$ENABLED" | grep -q "monitoring.googleapis.com" && pass "Cloud Monitoring API enabled." \
                                                       || fail "Cloud Monitoring API disabled."

# ---------- summary -------------------------------------------------------------
printf "\n%s──────────────────────────────────────────────%s\n" "$BLD" "$RST"
printf "%sSummary%s  %s%d OK%s · %s%d to review%s · %s%d need action%s\n" \
  "$BLD" "$RST" "$GRN" "$PASS_N" "$RST" "$YLW" "$WARN_N" "$RST" "$RED" "$FAIL_N" "$RST"
if (( FAIL_N > 0 )); then
  printf "Next step: the %sfirst-week plan%s in docs/ turns these into a prioritized fix list.\n" "$BLD" "$RST"
else
  printf "Healthy baseline. The next win is usually cost tuning and CI/CD hardening.\n"
fi
