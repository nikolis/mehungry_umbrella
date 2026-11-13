# Literature full-text — licensing & integrity gate

> **RETIRED (2026-11-12, same day).** Superseded by the biomed-fact-miner reshape: condition research
> now comes from `Mehungry.FactMining` (per-fact licence from the miner), so the standalone
> `/professional/full-text-licensing` admin page and the `FullTextRemediation` Europe-PMC sweep were
> **removed before the prod remediation was ever run**. The licence *concepts* here still apply, but
> enforcement moved into `FactMining.map_fact_sheet/3` (store a `quote` only for `commercial_ok`).
> `Mehungry.Literature.{License, FullTextIntegrity}` + the `study_full_texts` licence columns survive,
> now backing only the dormant legacy full-text reader shell. See
> `docs/implementation/fact_mining.md` and `docs/features/professionals/research_search.md`. The text
> below is kept for the legal rationale only.

> Status: **shipped 2026-11-12 → retired same day (see banner above).** Addresses two defects found
> auditing the stored `study_full_texts` corpus (see `legal_review_2026-10.md` for the broader review).

## The problem

The nutritionist research reader (`/nutritionist/research/:condition_id/paper/:study_id`)
renders the **verbatim full body** of papers, sourced from PubMed Central by the (now
being deprecated) `mehungry_extractor`. An audit of the live corpus (295 full-text
papers) found:

1. **No licence signal.** Most PMC full text is *not* freely redistributable. Europe PMC
   per-PMID lookup showed only ~60% CC BY; ~40% was CC BY-NC / NC-ND / NC-SA or had no OA
   licence. Displaying those verbatim in a commercial product is infringement, and the
   reader showed no attribution.
2. **Content mismatch.** The extractor did a loose PMID→PMCID `elink`; when the real full
   text wasn't in PMC it stored a **different, topically-related** article's text (an
   `elink` *neighbor*) under the correct citation — e.g. PMID 2122965 ("liquid diet for
   dysphagic horses") carried a body about *Clostridia*. Because claims are extracted from
   the body, those papers' claims are wrong too.

Two facts shaped the fix: every row carried `source_type = "open_access"` (that label only
means "a body parsed"), and `study_full_texts.pmcid` was NULL on every row — so the DB held
no trustworthy provenance.

## Why provenance, not text-overlap

The first instinct — compare the paper's abstract to its body to detect mismatches — **does
not work**: the substitute is a *related* paper, so it shares the cited paper's vocabulary.
Empirically the confirmed-mismatch PMID 2122965 scored 0.74 abstract/body containment, and
every paper's distinctive title terms appeared in its body. No text-only signal separates
"this paper" from "a close neighbor."

The reliable discriminator is **PMC Open Access subset membership**. A paper genuinely in
the OA subset has its *own* PMCID, so the fetch returned the right article; one that is not
in the subset could only have been a neighbor substitution. `Mehungry.Literature.FullTextIntegrity`
confirms membership + reads the real licence **per-PMID via Europe PMC** (`:europepmc_client`
seam).

## Data model (`study_full_texts`)

Migration `20261112120000_add_license_to_study_full_texts`:

- `license` / `license_url` — normalized licence (`Mehungry.Literature.License`).
- `full_text_displayable :boolean default false` — the explicit reader gate.
- `integrity_status` — `verified` | `pending_review` | `mismatch`.

`License.reusable?/1` is the display rule: **only `cc0` / `cc-by` / `cc-by-sa`** may be
shown verbatim. `full_text_displayable = verified AND reusable`.

## Behaviour

- **Store** (`StudyAnalyses.maybe_store_full_text/2`) — new full text is trusted only when
  the payload asserts `full_text_verified: true`; otherwise it is stored `pending_review`
  (hidden). Since the extractor seam is being deprecated and never set that, any future
  ingest is fail-safe hidden until verified.
- **Reader gate** — `full_text_for_reader/1` and the results-card outline
  (`full_text_outlines/1`) only surface a `full_text_displayable AND verified` paper. A
  licence-restricted (Class B) paper keeps its claims + PubMed link and shows a "full text
  not shown" chip (`has_restricted_full_text`).
- **Attribution** — the reader renders a required credit footer (source PMC + PMCID, licence
  name linking the CC deed, "retrieved via Europe PMC").

## Disposition classes

| Class | Condition | Reader | Claims / citation |
|---|---|---|---|
| **A displayable** | OA subset + `cc0`/`cc-by`/`cc-by-sa` | shown + attribution | kept |
| **B restricted** | OA subset + NC/ND/… | hidden | kept (facts, PubMed link) |
| **C mismatch** | not in OA subset, no licence | purged | invalidated (analysis `error: content_mismatch`) |
| **review** | ambiguous (lookup failed, or CC-licensed but not OA-flagged) | hidden | kept, queued |

## Remediating production state

Runs from the admin UI — **`/professional/full-text-licensing`** (admin, `:default2`) — not
a mix task (mix isn't runnable on the Fly release). "Run remediation" enqueues
`Mehungry.ObanWorkers.FullTextRemediationWorker` (`:imports`, one-at-a-time), which calls
`FullTextRemediation.remediate_all/1`: verify every stored full text via Europe PMC, apply
the disposition, broadcast live progress. Idempotent (re-runnable). It needs **only Europe
PMC** — not the extractor.

The page shows the live corpus breakdown and the **review queue** (Keep / Purge / Re-verify)
for `pending_review` papers.

Expected end state for the audited 295: **170 displayable · 42 restricted · 71 purged · 12
review** (validated against the Europe PMC audit).

## Key modules

- `Mehungry.Literature.License` — licence vocabulary + `reusable?/1`.
- `Mehungry.Literature.FullTextIntegrity` — OA/licence verification (`verify/1`,
  `classify/1`, `decision/1`) + `:europepmc_client` seam.
- `Mehungry.Literature.FullTextRemediation` + `ObanWorkers.FullTextRemediationWorker` — the
  admin sweep + review-queue actions.
- `Mehungry.Literature.StudyAnalyses` — `maybe_store_full_text/2`, the reader gates,
  `apply_full_text_verification/2`, `purge_full_text_mismatch/2`.
- `MehungryWeb.ProfessionalLive.FullTextLicensing` — the admin surface.
