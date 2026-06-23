<!-- BEGIN FOREMAN -->
## Foreman task board

You have access to the Foreman task board for project "bitcoin-insight" via MCP (tool prefix: foreman_*).

The board is OPT-IN. For a quick one-off fix, exploration, or board-free coding, just do the work — you do NOT need to touch Foreman. Engage the board only when the human points you at it (e.g. "work the board", "what's next", "handle the planned cards", "log this as a task").

When you DO work the board this session, orient first:
1. get_project_brain("bitcoin-insight") — loads project memory and structure map
2. list_tasks("bitcoin-insight") — loads the board with your goals and context injected

FIRST-TIME SETUP — do this ONCE, only if the board is still empty (get_project_context("bitcoin-insight") returns no goals/context AND get_project_brain("bitcoin-insight") is empty). That means Foreman was just connected to an existing codebase, so bootstrap it from the repo:
1. Read the codebase: README, package manifest, directory layout, key entry points.
2. set_project_context("bitcoin-insight", goals, context) — goals = what this project is and aims to achieve; context = tech stack, conventions, architecture rules an agent must respect. (Fills only empty fields; it never overwrites the human's edits.)
3. update_project_brain("bitcoin-insight", structure, progress_log) — structure = a pointer map of where things live; progress_log = current state and notable recent decisions.
4. create_task("bitcoin-insight", …) for the obvious next steps, bugs, or TODOs you found in the code.
5. Tell the human you bootstrapped the board from the codebase and ask them to review/refine the Kontext tab.
On later sessions the board is already populated — skip setup.

When you finish a board task, call submit_review(id, review, comment) — Foreman routes the card for you:
- review = "human" (simple things, design, bugs to test by hand), "agent" (you self-review — very technical / hard for a human to verify quickly, OR a tiny change you're highly confident in), or "both".
- comment = "REVIEW: <plain summary for the human + numbered verification steps>".
- The card goes to Needs Review, UNLESS the human opted that review type into auto-Done — then it lands directly in Done. get_project_context("bitcoin-insight") returns autoDoneReviews; for an auto-Done type you MUST first verify (run the tests/checks) and document them in the comment, since it skips human review.

After a structural change (files added/moved/renamed, a feature finished, a decision made): call update_project_brain("bitcoin-insight", …) so the structure map + progress log stay current — the next session reads them to orient.

When you pick up a "Needs Iteration" card: get_review_feedback(id) returns just the human feedback you haven't addressed yet — act on that instead of re-reading the whole history.

When asked to PLAN (not build) something: break the work into separate create_task cards — each a concrete, reviewable step — so the plan is a set of board cards the human can review before any code, instead of doing it all inline.

When unsure what to work on: suggest_next_task("bitcoin-insight")
<!-- END FOREMAN -->
