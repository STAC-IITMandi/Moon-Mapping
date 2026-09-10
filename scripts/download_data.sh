#!/usr/bin/env bash
#
# download_data.sh — fetch and lay out the datasets this repository needs.
#
# None of the imagery is stored in git: the Chandrayaan-2 products come from
# ISRO's PRADAN portal and the LRO NAC products come from ASU's LROC archive.
# This script pulls them from those original sources and arranges them in the
# directory layout the notebooks and scripts here expect.
#
# Usage:
#   scripts/download_data.sh <command> [options]
#
# Commands:
#   dirs                Create the empty data directory skeleton
#   nac                 Download LRO NAC images from the LROC archive  (public)
#   swinir-weights      Download upstream SwinIR pretrained weights    (public)
#   ohrc                Download Chandrayaan-2 OHRC products from PRADAN  (login)
#   tmc                 Download Chandrayaan-2 TMC-2 products from PRADAN  (login)
#   pradan-script FILE  Download every product listed in a PRADAN-generated script
#   all                 dirs + nac + swinir-weights  (everything not needing a login)
#
# Run `scripts/download_data.sh help <command>` for per-command options.
#
# See DATA.md for the full walkthrough, including how to get a PRADAN session.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_ROOT="${MOON_MAPPING_DATA:-$REPO_ROOT/data}"

# --- PRADAN (ISRO / ISSDC) -------------------------------------------------
PRADAN_BASE="https://pradan.issdc.gov.in"
PRADAN_ARCHIVE="/ch2/protected/downloadData/POST_OD/isda_archive/ch2_bundle/cho_bundle/nop"
PRADAN_KEEPALIVE="/ch2/protected/payload.xhtml"

# --- LROC (ASU) ------------------------------------------------------------
LROC_LOOKUP="https://data.lroc.im-ldi.com/lroc/view_lroc/LRO-L-LROC-2-EDR-V1.0"

# --- politeness: PRADAN enforces rate limits and will block abuse ----------
SLEEP_BETWEEN="${SLEEP_BETWEEN:-5}"

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
info()  { printf '%s==>%s %s\n' "$GRN" "$RST" "$*"; }
warn()  { printf '%s[warn]%s %s\n' "$YLW" "$RST" "$*" >&2; }
die()   { printf '%s[error]%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
step()  { printf '%s  - %s%s\n' "$DIM" "$*" "$RST"; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."; }

# ---------------------------------------------------------------------------
# dirs
# ---------------------------------------------------------------------------
# Mirrors the PDS4 bundle layout that PRADAN ships, because the parsing code
# (DataSet/Generator.py, DataSet/Gen2.py) walks 'data/<level>/<date>/' and
# derives the matching 'browse/<level>/<date>/' path from it.
cmd_dirs() {
  info "Creating data skeleton under $DATA_ROOT"
  local d
  for d in \
    "OHRC/files/data/raw"          "OHRC/files/data/calibrated" \
    "OHRC/files/browse/raw"        "OHRC/files/browse/calibrated" \
    "OHRC/files/geometry/calibrated" \
    "OHRC/files/miscellaneous/raw" "OHRC/files/miscellaneous/calibrated" \
    "OHRC/zips" \
    "TMC/zips" "TMC/derived" \
    "NAC/EDR" "NAC/CDR" \
    ; do
    mkdir -p "$DATA_ROOT/$d"; step "$d"
  done
  # TMC browse imagery is organised by year, as browse_calibrated_<year>/dir_<year>/<date>/
  for y in 2019 2020 2021 2022; do
    mkdir -p "$DATA_ROOT/TMC/browse_calibrated_$y/dir_$y"; step "TMC/browse_calibrated_$y/dir_$y"
  done
  cat > "$DATA_ROOT/README.md" <<'EOF'
# data/

Created by `scripts/download_data.sh`. Nothing in here is tracked by git.

Set `MOON_MAPPING_DATA` to keep the data somewhere else (another disk, a
network mount) and re-run the script; every command honours that variable.
EOF
  info "Done. Data root: $DATA_ROOT"
}

# ---------------------------------------------------------------------------
# PRADAN helpers
# ---------------------------------------------------------------------------
require_cookie() {
  [[ -n "${PRADAN_JSESSIONID:-}" ]] || die "PRADAN_JSESSIONID is not set.
  PRADAN products sit behind a login, so this script needs the session cookie
  from a browser where you are already signed in. See DATA.md for the exact
  click-path. Then:

      export PRADAN_JSESSIONID=<the JSESSIONID value>"
}

# PRADAN times a session out if it sees no traffic. The portal's own generated
# scripts poll payload.xhtml every 10 minutes; do the same while we download.
KEEPALIVE_PID=""
start_keepalive() {
  ( while true; do
      sleep 600
      curl -s -o /dev/null --max-time 60 \
        -H "Cookie: JSESSIONID=$PRADAN_JSESSIONID" \
        "$PRADAN_BASE$PRADAN_KEEPALIVE" || true
    done ) &
  KEEPALIVE_PID=$!
}
stop_keepalive() { [[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null || true; }
trap stop_keepalive EXIT INT TERM

# Fetch one PRADAN URL to a file, or fail.
#
# An expired or invalid session does not produce an HTTP error — PRADAN answers
# 302 to the login page, which curl reports as success with an empty body. So
# check the status code explicitly, and confirm we really got a zip rather than
# a login page, instead of trusting curl's exit status alone.
pradan_fetch_to() {
  local url="$1" out="$2" code
  code="$(curl -sS --max-redirs 0 --max-time 3600 \
            -H "Cookie: JSESSIONID=$PRADAN_JSESSIONID" \
            -o "$out.part" -w '%{http_code}' "$url" 2>/dev/null || echo 000)"
  if [[ "$code" != 200 ]] || [[ ! -s "$out.part" ]]; then
    rm -f "$out.part"
    warn "HTTP $code for $(basename "${url%%\?*}")"
    return 1
  fi
  # PRADAN products are zips; anything else means we were handed a web page.
  if [[ "$(head -c 2 "$out.part")" != "PK" ]]; then
    rm -f "$out.part"
    warn "response for $(basename "${url%%\?*}") was not a zip archive"
    return 1
  fi
  mv "$out.part" "$out"
}

# Processing level is encoded in the product name: ch2_<inst>_n{r,c,d}?_...
#   nr* -> raw     nc* -> calibrated     nd* -> derived
level_of() {
  case "${1#ch2_*_n}" in
    r*) echo raw ;;
    c*) echo calibrated ;;
    d*) echo derived ;;
    *)  echo "" ;;
  esac
}

# ch2_ohr_ncp_20230823T1450475804_d_img_n18.zip -> 20230823
date_of() {
  local ts="${1#ch2_*_*_}"
  echo "${ts:0:8}"
}

# Download one product zip. $1=instrument (ohrc|tmc) $2=product filename
pradan_get() {
  local inst="$1" product="$2"
  local coll level date url out
  case "$inst" in
    ohrc) coll="ohr_collection" ;;
    tmc)  coll="tmc_collection" ;;
    *) die "unknown instrument '$inst'" ;;
  esac
  level="$(level_of "$product")"
  date="$(date_of "$product")"
  [[ -n "$level" && -n "$date" ]] || { warn "cannot parse '$product' — skipping"; return 0; }

  case "$inst" in
    ohrc) out="$DATA_ROOT/OHRC/zips/$product" ;;
    tmc)  out="$DATA_ROOT/TMC/zips/$product" ;;
  esac

  if [[ -s "$out" ]]; then step "have $product"; return 0; fi

  url="$PRADAN_BASE$PRADAN_ARCHIVE/$coll/data/$level/$date/$product?$inst"
  step "$product  ($level/$date)"
  mkdir -p "$(dirname "$out")"
  if ! pradan_fetch_to "$url" "$out"; then
    warn "failed: $product
    A failure here usually means the session expired, or a download/rate limit
    was hit. Log in again, re-export PRADAN_JSESSIONID and re-run — completed
    files are skipped automatically."
    return 1
  fi
  sleep "$SLEEP_BETWEEN"
}

# Unzip products into the PDS4 tree the parsing code walks.
pradan_extract() {
  local inst="$1" dest
  case "$inst" in
    ohrc) dest="$DATA_ROOT/OHRC/files" ;;
    tmc)  dest="$DATA_ROOT/TMC" ;;
  esac
  shopt -s nullglob
  local zips=("$DATA_ROOT/$( [[ $inst == ohrc ]] && echo OHRC || echo TMC )/zips"/*.zip)
  shopt -u nullglob
  [[ ${#zips[@]} -gt 0 ]] || return 0
  need unzip
  info "Extracting ${#zips[@]} $inst product(s) into $dest"
  local z
  for z in "${zips[@]}"; do
    step "$(basename "$z")"
    unzip -qo "$z" -d "$dest"
  done
}

# Read product names from a CSV column, ignoring the header.
products_from_csv() {
  local csv="$1" col="$2"
  [[ -f "$csv" ]] || die "missing catalogue: $csv"
  python3 - "$csv" "$col" <<'PY'
import csv, sys
path, col = sys.argv[1], sys.argv[2]
with open(path, newline='', encoding='utf-8', errors='replace') as fh:
    for row in csv.DictReader(fh):
        v = (row.get(col) or '').strip()
        if v.endswith('.zip'):
            print(v)
PY
}

# ---------------------------------------------------------------------------
# ohrc
# ---------------------------------------------------------------------------
cmd_ohrc() {
  local limit=0 products=() extract=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      --product) products+=("$2"); shift 2 ;;
      --no-extract) extract=0; shift ;;
      *) die "unknown option for 'ohrc': $1" ;;
    esac
  done
  require_cookie; need curl; cmd_dirs >/dev/null

  if [[ ${#products[@]} -eq 0 ]]; then
    # ohrc.csv holds corner coordinates but no product names, so fall back to
    # the OHRC shapefile attribute table, which does.
    local shp="$REPO_ROOT/DataSet/OHRC_ShapeFiles/ch2_ohr_cal.dbf"
    [[ -f "$shp" ]] || die "no --product given and $shp is missing"
    mapfile -t products < <(python3 - "$shp" <<'PY'
import sys
# Minimal DBF reader: enough to pull the product-id column out of the
# ISRO-supplied OHRC shapefile without adding a dependency.
with open(sys.argv[1], 'rb') as fh:
    data = fh.read()
nrec = int.from_bytes(data[4:8], 'little')
hlen = int.from_bytes(data[8:10], 'little')
rlen = int.from_bytes(data[10:12], 'little')
fields, off = [], 32
while data[off] != 0x0D:
    name = data[off:off+11].split(b'\x00')[0].decode('ascii', 'replace')
    size = data[off+16]
    fields.append((name, size)); off += 32
names = [f[0].lower() for f in fields]
# DOWNLOAD carries the exact zip filename; PRODUCT_ID needs '.zip' appended.
target = next((i for i, n in enumerate(names) if n == 'download'), None)
if target is None:
    target = next((i for i, n in enumerate(names) if 'prod' in n), None)
if target is None:
    sys.exit(0)
for r in range(nrec):
    base = hlen + r*rlen + 1
    pos = base
    for i, (nm, size) in enumerate(fields):
        if i == target:
            v = data[pos:pos+size].decode('ascii', 'replace').strip()
            if v:
                print(v if v.endswith('.zip') else v + '.zip')
            break
        pos += size
PY
)
    [[ ${#products[@]} -gt 0 ]] || die "could not read product names from the OHRC shapefile.
  Pass them explicitly instead:  scripts/download_data.sh ohrc --product ch2_ohr_ncp_....zip
  or reuse a PRADAN-generated script:  scripts/download_data.sh pradan-script mycart.sh"
  fi

  if [[ "$limit" -gt 0 && ${#products[@]} -gt "$limit" ]]; then
    products=("${products[@]:0:$limit}")
  fi
  info "OHRC: ${#products[@]} product(s) queued"
  start_keepalive
  local failed=0
  for p in "${products[@]}"; do pradan_get ohrc "$p" || { failed=1; break; }; done
  stop_keepalive
  if [[ "$extract" -eq 1 ]]; then pradan_extract ohrc; fi
  if [[ "$failed" -eq 0 ]]; then info "OHRC done."
  else warn "OHRC stopped early — re-run to resume."; fi
}

# ---------------------------------------------------------------------------
# tmc
# ---------------------------------------------------------------------------
cmd_tmc() {
  local limit=0 products=() extract=1 csv="$REPO_ROOT/DataSet/TMC/coordinates.csv" col="Filename"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      --product) products+=("$2"); shift 2 ;;
      --csv) csv="$2"; shift 2 ;;
      --column) col="$2"; shift 2 ;;
      --ortho) csv="$REPO_ROOT/dataset-cleaning-creation-and-analysis/dataset-preparation/csv_files/tmc_oth.csv"; col="name"; shift ;;
      --no-extract) extract=0; shift ;;
      *) die "unknown option for 'tmc': $1" ;;
    esac
  done
  require_cookie; need curl; cmd_dirs >/dev/null

  if [[ ${#products[@]} -eq 0 ]]; then
    mapfile -t products < <(products_from_csv "$csv" "$col")
    info "Read ${#products[@]} TMC product name(s) from $(basename "$csv")"
  fi
  if [[ "$limit" -gt 0 && ${#products[@]} -gt "$limit" ]]; then
    products=("${products[@]:0:$limit}")
  fi
  [[ ${#products[@]} -gt 0 ]] || die "no TMC products to download"

  warn "The TMC archive path is inferred by analogy with the OHRC one, which is
  the only layout the sample PRADAN scripts in docs/ actually document. If these
  requests 404, generate a script from your PRADAN cart and run:
      scripts/download_data.sh pradan-script <that-script.sh>
  which uses the portal's own paths and is always correct."

  info "TMC: ${#products[@]} product(s) queued"
  start_keepalive
  local failed=0
  for p in "${products[@]}"; do pradan_get tmc "$p" || { failed=1; break; }; done
  stop_keepalive
  if [[ "$extract" -eq 1 ]]; then pradan_extract tmc; fi
  if [[ "$failed" -eq 0 ]]; then info "TMC done."
  else warn "TMC stopped early — re-run to resume."; fi
}

# ---------------------------------------------------------------------------
# pradan-script — replay the paths out of a script PRADAN generated for you
# ---------------------------------------------------------------------------
cmd_pradan_script() {
  local src="${1:-}"
  [[ -n "$src" && -f "$src" ]] || die "usage: download_data.sh pradan-script <pradan-generated-script.sh>"
  need curl

  # Prefer the caller's own cookie; otherwise reuse the one PRADAN baked into
  # the script. This has to happen before require_cookie, or the fallback is
  # unreachable.
  if [[ -z "${PRADAN_JSESSIONID:-}" ]]; then
    local embedded
    embedded="$(sed -n 's/^cookies="JSESSIONID=\(.*\)"$/\1/p' "$src" | head -1)"
    if [[ -n "$embedded" && "$embedded" != *PASTE* ]]; then
      PRADAN_JSESSIONID="$embedded"
      info "Using the JSESSIONID embedded in $(basename "$src")"
    fi
  fi
  require_cookie; cmd_dirs >/dev/null

  mapfile -t paths < <(grep -oE '"/ch2/protected/downloadData[^"]*"' "$src" | tr -d '"')
  [[ ${#paths[@]} -gt 0 ]] || die "no product paths found in $src"
  info "Replaying ${#paths[@]} product path(s) from $(basename "$src")"
  start_keepalive
  local inst product out
  for path in "${paths[@]}"; do
    inst="${path##*\?}"; product="${path##*/}"; product="${product%%\?*}"
    case "$inst" in
      ohrc) out="$DATA_ROOT/OHRC/zips/$product" ;;
      tmc)  out="$DATA_ROOT/TMC/zips/$product" ;;
      *)    out="$DATA_ROOT/other/$product" ;;
    esac
    if [[ -s "$out" ]]; then step "have $product"; continue; fi
    step "$product"
    mkdir -p "$(dirname "$out")"
    if ! pradan_fetch_to "$PRADAN_BASE$path" "$out"; then
      warn "failed at $product — session expired or limit reached. Re-run to resume."
      break
    fi
    sleep "$SLEEP_BETWEEN"
  done
  stop_keepalive
  pradan_extract ohrc
  pradan_extract tmc
}

# ---------------------------------------------------------------------------
# nac — LRO NAC from the LROC archive (no login required)
# ---------------------------------------------------------------------------
# The CSVs in this repo list CDR product ids (…LC / …RC). The EDRs the ISIS
# pipeline in dataset-cleaning-creation-and-analysis/scripts/nac2png.sh expects
# are the same ids with the trailing C swapped for E (…LE / …RE).
cmd_nac() {
  local limit=25 ids=() kind="EDR"
  local csv="$REPO_ROOT/dataset-cleaning-creation-and-analysis/dataset-preparation/csv_files/nac_names.csv"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      --id) ids+=("$2"); shift 2 ;;
      --csv) csv="$2"; shift 2 ;;
      --cdr) kind="CDR"; shift ;;
      --all) limit=0; shift ;;
      *) die "unknown option for 'nac': $1" ;;
    esac
  done
  need curl; cmd_dirs >/dev/null

  if [[ ${#ids[@]} -eq 0 ]]; then
    [[ -f "$csv" ]] || die "missing $csv"
    mapfile -t ids < <(python3 - "$csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as fh:
    for row in csv.DictReader(fh):
        v = (row.get('name') or '').strip()
        if v:
            print(v)
PY
)
    local total=${#ids[@]}
    info "Read $total NAC product id(s) from $(basename "$csv")"
    if [[ "$limit" -gt 0 && "$total" -gt "$limit" ]]; then
      ids=("${ids[@]:0:$limit}")
      warn "Limiting to the first $limit. NAC images are ~250 MB each — all
  $total would be roughly $((total / 4)) TB. Use --limit N, or --all deliberately."
    fi
  fi

  local dest="$DATA_ROOT/NAC/$kind"
  mkdir -p "$dest"
  info "NAC: fetching ${#ids[@]} $kind image(s) into $dest"
  local edr_id url out ok=0 miss=0
  for pid in "${ids[@]}"; do
    if [[ "$kind" == EDR ]]; then edr_id="${pid%C}E"; else edr_id="${pid%E}C"; fi
    out="$dest/$edr_id.IMG"
    if [[ -s "$out" ]]; then step "have $edr_id"; ok=$((ok+1)); continue; fi
    # Resolve the product id to its volume path; the archive is not laid out
    # predictably from the id alone. An unknown id yields no match, and with
    # `pipefail` that would abort the run — so absorb the failure and warn.
    url="$(curl -sL --max-time 120 "$LROC_LOOKUP/${pid%C}E" \
           | grep -oiE 'href="[^"]*'"$kind"'[^"]*\.IMG"' \
           | sed 's/href="//; s/"$//' | head -1 || true)"
    if [[ -z "$url" ]]; then warn "could not resolve $edr_id"; miss=$((miss+1)); continue; fi
    [[ "$url" == //* ]] && url="https:$url"
    step "$edr_id"
    if curl -fsSL --max-time 7200 -o "$out.part" "$url"; then
      mv "$out.part" "$out"; ok=$((ok+1))
    else
      rm -f "$out.part"; warn "download failed for $edr_id"; miss=$((miss+1))
    fi
  done
  info "NAC done: $ok retrieved, $miss missing."
  if [[ "$kind" == EDR ]]; then cat <<EOF

  ${DIM}EDRs are raw. To calibrate them to PNG, install USGS ISIS and run
  dataset-cleaning-creation-and-analysis/scripts/nac2png.sh from $dest${RST}
EOF
  fi
}

# ---------------------------------------------------------------------------
# swinir-weights
# ---------------------------------------------------------------------------
cmd_swinir_weights() {
  need curl
  local dest="$REPO_ROOT/AI Models/SwinIR/experiments/pretrained_models"
  local zoo="$REPO_ROOT/AI Models/SwinIR/model_zoo/swinir"
  mkdir -p "$dest" "$zoo"
  local rel="https://github.com/JingyunLiang/SwinIR/releases/download/v0.0"
  info "Downloading upstream SwinIR weights into AI Models/SwinIR/"
  local f
  for f in \
    003_realSR_BSRGAN_DFO_s64w8_SwinIR-M_x4_GAN.pth \
    003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_GAN.pth \
    004_grayDN_DFWB_s128w8_SwinIR-M_noise15.pth \
    004_grayDN_DFWB_s128w8_SwinIR-M_noise25.pth \
    004_grayDN_DFWB_s128w8_SwinIR-M_noise50.pth \
    005_colorDN_DFWB_s128w8_SwinIR-M_noise15.pth \
    005_colorDN_DFWB_s128w8_SwinIR-M_noise25.pth \
    005_colorDN_DFWB_s128w8_SwinIR-M_noise50.pth \
    006_CAR_DFWB_s126w7_SwinIR-M_jpeg10.pth \
    006_CAR_DFWB_s126w7_SwinIR-M_jpeg20.pth \
    006_CAR_DFWB_s126w7_SwinIR-M_jpeg30.pth \
    006_CAR_DFWB_s126w7_SwinIR-M_jpeg40.pth \
    ; do
    if [[ -s "$dest/$f" ]]; then step "have $f"; continue; fi
    step "$f"
    curl -fsSL --max-time 3600 -o "$dest/$f.part" "$rel/$f" \
      && mv "$dest/$f.part" "$dest/$f" \
      || { rm -f "$dest/$f.part"; warn "failed: $f"; }
  done
  f=001_classicalSR_DIV2K_s48w8_SwinIR-M_x2.pth
  if [[ ! -s "$zoo/$f" ]]; then
    step "$f"
    curl -fsSL --max-time 3600 -o "$zoo/$f.part" "$rel/$f" \
      && mv "$zoo/$f.part" "$zoo/$f" || { rm -f "$zoo/$f.part"; warn "failed: $f"; }
  fi
  info "SwinIR weights done."
  warn "The project's own trained checkpoints (SRGAN g_best.pth.tar, the SwinIR
  L1/SSIM/perceptual-loss runs) were never published to a public mirror. They
  live only in the project Google Drive — see DATA.md."
}

# ---------------------------------------------------------------------------
cmd_help() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; /^set -euo/d'
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    dirs)            cmd_dirs "$@" ;;
    nac)             cmd_nac "$@" ;;
    swinir-weights)  cmd_swinir_weights "$@" ;;
    ohrc)            cmd_ohrc "$@" ;;
    tmc)             cmd_tmc "$@" ;;
    pradan-script)   cmd_pradan_script "$@" ;;
    all)             cmd_dirs; cmd_nac --limit 4; cmd_swinir_weights ;;
    help|-h|--help)  cmd_help ;;
    *) die "unknown command '$cmd'. Run: scripts/download_data.sh help" ;;
  esac
}
main "$@"
