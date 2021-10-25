#!/bin/bash

# shellcheck source=../actions.sh
source /usr/local/actions.sh

debug
setup
init-backend
select-workspace
set-plan-args

PLAN_OUT="$STEP_TMP_DIR/plan.out"

if [[ -v GITHUB_TOKEN ]]; then
    update_status "Applying plan in $(job_markdown_ref)"
fi

exec 3>&1

function apply() {

    set +e
    # shellcheck disable=SC2086
    (cd "$INPUT_PATH" && terraform apply -input=false -no-color -auto-approve -lock-timeout=300s $PLAN_OUT) | $TFMASK
    local APPLY_EXIT=${PIPESTATUS[0]}
    set -e

    if [[ $APPLY_EXIT -eq 0 ]]; then
        update_status "Plan applied in $(job_markdown_ref)"
    else
        set_output failure-reason apply-failed
        update_status "Error applying plan in $(job_markdown_ref)"
        exit 1
    fi
}

### Generate a plan

plan

if [[ $PLAN_EXIT -eq 1 ]]; then
    if grep -q "Saving a generated plan is currently not supported" "$STEP_TMP_DIR/terraform_plan.stderr"; then
        set-remote-plan-args
        PLAN_OUT=""

        if [[ "$INPUT_AUTO_APPROVE" == "true" ]]; then
            # The apply will have to generate the plan, so skip doing it now
            PLAN_EXIT=2
        else
            plan
        fi
    fi
fi

if [[ $PLAN_EXIT -eq 1 ]]; then
    cat "$STEP_TMP_DIR/terraform_plan.stderr"

    update_status "Error applying plan in $(job_markdown_ref)"
    exit 1
fi

### Apply the plan

if [[ "$INPUT_AUTO_APPROVE" == "true" || $PLAN_EXIT -eq 0 ]]; then
    echo "Automatically approving plan"
    apply

else

    if [[ "$GITHUB_EVENT_NAME" != "push" && "$GITHUB_EVENT_NAME" != "pull_request" && "$GITHUB_EVENT_NAME" != "issue_comment" && "$GITHUB_EVENT_NAME" != "pull_request_review_comment" && "$GITHUB_EVENT_NAME" != "pull_request_target" && "$GITHUB_EVENT_NAME" != "pull_request_review" ]]; then
        echo "Could not fetch plan from the PR - $GITHUB_EVENT_NAME event does not relate to a pull request. You can generate and apply a plan automatically by setting the auto_approve input to 'true'"
        exit 1
    fi

    if [[ ! -v GITHUB_TOKEN ]]; then
        echo "GITHUB_TOKEN environment variable must be set to get plan approval from a PR"
        echo "Either set the GITHUB_TOKEN environment variable or automatically approve by setting the auto_approve input to 'true'"
        echo "See https://github.com/dflook/terraform-github-actions/ for details."
        exit 1
    fi

    if ! github_pr_comment get "$STEP_TMP_DIR/approved-plan.txt" 2>"$STEP_TMP_DIR/github_pr_comment.stderr"; then
        debug_file "$STEP_TMP_DIR/github_pr_comment.stderr"
        echo "Plan not found on PR"
        echo "Generate the plan first using the dflook/terraform-plan action. Alternatively set the auto_approve input to 'true'"
        echo "If dflook/terraform-plan was used with add_github_comment set to changes-only, this may mean the plan has since changed to include changes"

        set_output failure-reason plan-changed
        exit 1
    else
        debug_file "$STEP_TMP_DIR/github_pr_comment.stderr"
    fi

    if plan_cmp "$STEP_TMP_DIR/plan.txt" "$STEP_TMP_DIR/approved-plan.txt"; then
        apply
    else
        echo "Not applying the plan - it has changed from the plan on the PR"
        echo "The plan on the PR must be up to date. Alternatively, set the auto_approve input to 'true' to apply outdated plans"
        update_status "Plan not applied in $(job_markdown_ref) (Plan has changed)"

        echo "Plan changes:"
        debug_log diff "$STEP_TMP_DIR/plan.txt" "$STEP_TMP_DIR/approved-plan.txt"
        diff "$STEP_TMP_DIR/plan.txt" "$STEP_TMP_DIR/approved-plan.txt" || true

        set_output failure-reason plan-changed
        exit 1
    fi
fi

output
