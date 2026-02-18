#!/bin/bash

REPO=${$REPO:-$(GH_PAGER=cat gh repo view --json nameWithOwner -q .nameWithOwner)}

echo "Repository: $REPO"

remove_run() {
  echo "Removing workflow: $run_id"

  curl -L \
    -X DELETE \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO/actions/runs/$1"
}

get_runs() {
  curl -sL \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO/actions/workflows/$1/runs?per_page=100&page=$2"
}

queued_workflow=()

while read -r workflow; do

  workflow_name="$(jq -r ".name" <<< "$workflow")"
  workflow_id="$(jq -r ".id" <<< "$workflow")"

  current_page=1

  echo "Processing workflow: '$workflow_name'..."

  workflow_count=0

  while :; do
    workflow_runs="$(get_runs "$workflow_id" "$current_page")"

    if (( $(jq '.workflow_runs | length' <<< "$workflow_runs") == 0 )); then
      break
    fi

    while read -r runs; do
      if (( $(date +%s) - $(date -d "$(echo "$runs" | jq -r '.updated_at')" +%s) >= ${WORKFLOW_AGE:-0} )); then

        queued_workflow+=("$(jq -r '.id' <<< "$runs")")
        ((workflow_count++))

      fi
    done < <(jq -c ".workflow_runs[]" <<< "$workflow_runs")
    ((current_page++))
  done

  echo "Queueing $workflow_count for deletion..."

done < <(
  echo "Getting 'https://api.github.com/repos/$REPO/actions/workflows'..."
  curl -sL \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$REPO/actions/workflows" \
  | jq -c ".workflows[]"
)

for run_id in "${queued_workflow[@]}"; do
  remove_run "$run_id"
done
