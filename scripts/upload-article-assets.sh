#!/usr/bin/env bash
# Upload article images to Cloudflare R2 (served at https://assets.crit.md).
#
# Prerequisites:
#   npx wrangler login
#   export CRIT_ASSETS_BUCKET=<your-r2-bucket-name>
#
# Usage:
#   ./scripts/upload-article-assets.sh [slug] [source-dir]
#
# Example:
#   ./scripts/upload-article-assets.sh how-to-plan-document-and-review \
#     ../crit-articles/how_to_plan_document_and_review

set -euo pipefail

slug="${1:-how-to-plan-document-and-review}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
default_src="${repo_root}/../crit-articles/how_to_plan_document_and_review"
src_dir="${2:-$default_src}"
bucket="${CRIT_ASSETS_BUCKET:-}"

if [[ -z "$bucket" ]]; then
  echo "Set CRIT_ASSETS_BUCKET to your R2 bucket name." >&2
  echo "List buckets after login: npx wrangler r2 bucket list" >&2
  exit 1
fi

if [[ ! -d "$src_dir" ]]; then
  echo "Source directory not found: $src_dir" >&2
  exit 1
fi

prefix="articles/${slug}"
shopt -s nullglob
files=("$src_dir"/*.{png,jpg,jpeg,webp,gif})

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No image files found in $src_dir" >&2
  exit 1
fi

echo "Uploading ${#files[@]} file(s) to ${bucket}/${prefix}/"
echo

for file in "${files[@]}"; do
  name="$(basename "$file")"
  key="${prefix}/${name}"
  case "$name" in
    *.png) content_type="image/png" ;;
    *.jpg|*.jpeg) content_type="image/jpeg" ;;
    *.webp) content_type="image/webp" ;;
    *.gif) content_type="image/gif" ;;
    *) content_type="application/octet-stream" ;;
  esac

  npx wrangler r2 object put "${bucket}/${key}" \
    --file="$file" \
    --content-type="$content_type" \
    --remote

  echo "https://assets.crit.md/${key}"
done

echo
echo "Done. Images are available at https://assets.crit.md/${prefix}/"
