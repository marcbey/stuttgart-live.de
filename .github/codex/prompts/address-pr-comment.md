# Codex PR Follow-up

You are working inside an existing pull request branch from a GitHub Actions job.

Apply the smallest correct follow-up change requested in the PR comment below.

Requirements:
- Treat the comment as targeted review feedback for the existing PR.
- Keep the diff narrow and avoid unrelated refactoring.
- Add or update tests if that is appropriate to prove the follow-up fix.
- Leave the pull request branch in a review-ready state.
- If the comment is unclear, avoid unsafe guessing. Make only a clearly justified minimal change, or stop and explain the blocker in your final message.

Pull request title:
{{PR_TITLE}}

Pull request body:
```text
{{PR_BODY}}
```

Comment author:
{{COMMENT_AUTHOR}}

Comment body:
```text
{{COMMENT_BODY}}
```

Comment context:
```text
{{COMMENT_CONTEXT}}
```
