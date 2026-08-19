"""Every AI job this app calls. Names are API — the Vault admin configures
which model serves each job by name, so renaming one means the admin has to
reconfigure it. See HICO Forge VCA Master Prompt §9.

Add one constant per job. Use stable snake_case verb_noun names:
    SUMMARIZE_TICKET = "summarize_ticket"
    DRAFT_REPLY = "draft_reply"

For any job whose answer must be a classification or another closed set of
values (no JSON mode is available from the broker — see §5.4), also define
the closed set and an "unknown" sentinel right here, next to the job name:

    CLASSIFY_FIT = "classify_fit"
    FIT_LEVELS = ("strong_yes", "yes", "no", "strong_no")  # closed set; app-owned
    FIT_UNKNOWN = "unknown"                                 # model didn't comply

Parse that job's response with a trimmed, case-insensitive exact match against
FIT_LEVELS; anything else maps to FIT_UNKNOWN and a visible "needs review"
state in the UI. Never coerce an unparseable answer to the nearest value, and
never retry-loop to coax the format.
"""

# TODO: replace with this app's real jobs.
EXAMPLE_JOB = "example_job"
