# Design — Nutritionist Research Search Engine (re-shaping the science pipeline)

> Status: **approved 2026-10-26; Phase 0 in progress.** Scope/decisions locked with the user.
> Phasing in §9; this doc is the living feature doc (refined as phases land).

## 1. Goal

A search engine of **pre-digested PubMed publications** for professional nutritionists. The
nutritionist types a condition term (e.g. *Ulcerative Colitis*), and gets rich, nutrition-relevant
results **per publication**:

- publication metadata — date, journal/source, authority signals, sample size (n participants), authors;
- **highlighted parts** of the publication (the extractor's provenance-backed claims) with a link
  to the source;
- results **grouped by research type** (systematic review / meta-analysis → RCT → cohort → …).

## 2. Key reframe — the feature is ~70% already built

The admin LiveView `MehungryWeb.ProfessionalLive.HealthConditions` already:
- runs a **condition-seeded** PubMed crawl (`Literature.enqueue_condition_crawl` → `StudyCondition`,
  built around the literal `"Ulcerative Colitis diet"` example);
- calls the Python extractor `/analyze` and persists per-paper results via
  `Literature.store_analysis_response` → `StudyAnalysis`;
- renders per-paper cards with PubMed link, `study_design`, `publication_year`, `sample_size (n=)`,
  claim count, and each claim with its evidence span.

What it is **not**: nutritionist-facing (it's admin `:default2`), search-first (it's a
condition list you expand), grouped by research type, or decoupled from the compound/recommendation
curation apparatus it's buried inside.

**So the work is: (A) lift + regroup this into a clean nutritionist search feature, and
(B) decommission the compound/species/recommendation *generation* machinery around it.**

## 3. Decisions locked

| # | Decision | Choice |
|---|---|---|
| 1 | Delete scope | **Science pipeline only** — delete the discovery/curation *machinery*; keep consumer advise features |
| 2 | Destructiveness | **Decommission in place first** (reversible); hard-delete tables later |
| 3 | Acquisition | **Curated condition catalog** — admin pre-ingests; nutritionists search already-digested research |
| 4 | Access | **Nutritionist-gated only** — under `/nutritionist/**` |

### Reconciling #1 with "keep consumer advise"
Consumer features (condition-aware meal blueprints, recipe condition badges incl. mobile API,
`/foods` condition filter, AI-bot condition seeds, article refs) **read** curated advice. They do
**not** need the literature *generation* chain. So the rule is:

> Delete how facts/recommendations are **produced from literature** (crawl→annotate→derive→promote).
> Keep the curated **tables, already-promoted facts, and read paths** those consumer features use.

This is coherent: `Health.CompoundRecommendation` / `NutrientRecommendation` can be hand-curated;
`Health.species_for_condition/2` reads existing `SpeciesCompoundRelationship` rows; nutrient advice
reads USDA `IngredientNutrient`. None of those reads require PubTator, candidates, or Chemistry.

## 4. Target UX

```
/nutritionist/research                     ← search landing (condition autocomplete over the catalog)
/nutritionist/research/:condition_id       ← results page for a condition
```

**Search landing** = a box over the **full condition list** (`Literature.conditions_for_search/1`).
The page loads with **every** `Health.Condition` listed — those with digested research ranked
first (study count desc), then the rest alphabetically — each showing its non-error study count
(`0` when nothing is digested yet). Typing filters the list: the match is **fuzzy** on the
condition name — pg_trgm `word_similarity` over `unaccent`'d text (threshold `0.3`, mirroring
`Food.IngredientSearch`), so typos and reordered words still hit ("ulcerativ colitus" /
"colitis ulcerative" → "Ulcerative Colitis"); a plain substring match is always kept as well.
Filtered hits are ranked by similarity, then study count desc, then name. Opening a condition
with no digested research lands on the results page's "No digested research for this condition
yet." empty state (not a dead end). (`conditions_with_research/1` — the with-research-only catalog
— is retained for other callers but no longer backs the landing.)

**Filter + sort toolbar** (above the groups): one-click metadata filters — **Full text**
(open-access outline present), **MEDLINE-indexed** (`JournalAuthority.medline_indexed?`),
**Independent funding** (`funding_independence == "independent"`) — AND-combined, plus a **Sort**
select (Best match · Newest · Largest sample · Most findings). Filtering/sorting runs **in the
LiveView over the already-loaded groups** (no DB round-trip); groups left empty are hidden and the
header shows "Showing N of M".

**Results page** = the pre-digested research for one condition, **grouped by research type** in
evidence-hierarchy order, each group **collapsible** (native `<details>`, open by default) with a count:

1. Systematic review / meta-analysis
2. Randomized controlled trial
3. Cohort study
4. Case-control study
5. Cross-sectional / observational
6. Narrative review / other
7. Unknown design (shown last, de-emphasized)

**Result card** (per publication):
- Title (→ PubMed `https://pubmed.ncbi.nlm.nih.gov/<pmid>/`), authors, journal, date.
- Metadata chips: research type · year · **n = sample_size** · funding independence · source type
  (full-text vs abstract-only) · **journal authority** (SJR quartile — see §5a).
- **Section outline (full-text papers):** when the paper has open-access full text, the card carries
  a collapsed **"Read full text · N sections"** disclosure that expands to the paper's own **numbered
  table of contents** (`StudyFullText.sections`) — a numeric spine (tabular figures) with `x.y`
  subsections **nested under a collapsible top-level `x`** (the authors' heading numbers drive the
  hierarchy, parsed by `outline_tree/1`; a group with no parent heading in the source is labelled by
  its range, e.g. `2.1–2.3`). Each leaf deep-links into the in-app **reader** (below) scrolled to that
  section (`/nutritionist/research/:condition_id/paper/:study_id#sec-<section_id>`). Abstract-only
  papers keep only the PubMed title link (there is nothing to deep-link into).
- **Suggested notes — on demand:** the paper's curated claims (`StudyAnalysis.claims`) are hidden
  on first paint, behind a per-card **"Suggested notes (N)"** toggle (Alpine `x-show`, no server
  round-trip). Each is shown as its `subject_label → predicate → object_label` plus the **verbatim
  evidence sentence** (`quoted_text` from the claim's `evidence[]` span), with an **"Open in text"**
  link that deep-links into the in-app reader at the claim's first `evidence[].paragraph_id`
  (`#par-<paragraph_id>`), falling back to a PubMed "source" link when the paper has no full text.
  Only claims the admin curated as `food_related`/`general_science` surface to nutritionists;
  `wrong`/`ignore` are hidden (curation already exists via `StudyAnalyses.set_claim_position/3`).
  Each note also has a **Save** bookmark toggle + a per-paper **"Write your own note"** composer,
  persisted per nutritionist (`research_notes` / `Mehungry.Professionals.ResearchNotes`) and shown
  back on a standalone **"My notes"** page (`/nutritionist/research/notes`) — the **Suggested Notes**
  feature (`docs/features/professionals/research_notes.md`), Phases 1–2 shipped; client-condition
  surfacing (Phase 3) pending a structured client↔condition link.
- Provenance line: extractor run/pipeline version (trust/auditability).

**In-app reader** (`MehungryWeb.NutritionistLive.ResearchPaper`,
`/nutritionist/research/:condition_id/paper/:study_id`): renders the paper's stored
`StudyFullText.sections` with per-section (`#sec-<section_id>`) and per-paragraph
(`#par-<paragraph_id>`) anchors, so the card's section link scrolls straight to the deep-linked part.
Each paragraph's claim evidence spans are highlighted inline (`<mark>`, tinted by polarity) by making
the claim's absolute `evidence.start_char/end_char` paragraph-relative (subtract the paragraph's
`start_char`), via `Literature.full_text_for_reader/1`. Offered only for papers with a stored
full-text outline; a study without one redirects back to the condition's results page. The reader
also carries a **floating notes widget** (Save the paper's suggested notes + write your own against a
highlighted passage) — see the **Suggested Notes** feature (`docs/features/professionals/research_notes.md`).

### "Direct links to the part" — realistic interpretation  ✅ CONFIRMED ("yes for now") · reader DELIVERED 2026-10-26
PubMed has no char-offset deep-link, and PMC deep-links only to sections. True char-span
highlighting only works inside our **own rendered full-text view** — which now exists: the in-app
reader (above) renders the stored `StudyFullText.sections` with `#sec-`/`#par-` anchors and inline
`<mark>` highlighting of each claim's evidence span. Abstract-only papers (no full text) still fall
back to the verbatim quote inline + the PubMed link. Accepted as the honest ceiling for v1.

## 5. Data model — all KEPT, no new tables required for v1

| Table / module | Role in the feature |
|---|---|
| `Literature.ScientificStudy` | pmid, doi, title, abstract, journal, publication_date, authors, raw_metadata — the publication metadata |
| `Literature.StudyCondition` | condition ↔ study link from the condition-seeded crawl (the search join) |
| `Literature.StudyAnalysis` | the pre-digested payload: `claims` (w/ evidence spans), `study_design`, `sample_size`, `publication_year`, `source_type`, `funder_types`, `funding_independence`, per-claim `position` curation |
| `Literature.StudyFullText` | PMC OA full text — now stores the structured **`sections`** outline (jsonb: ordered sections → paragraphs, each with `title`/`start_char`/`end_char`/`text`) the enriched `/analyze` response carries for open-access papers. Powers the in-app reader's anchors + claim-span highlighting. Written by `StudyAnalyses.store_analysis_response/1` (abstract-only papers carry no sections → no row) |
| `Health.Condition` (+ identifier/translation/resolver/seeder/state) | the search vocabulary / catalog |
| `StudyAnalyses` context | `analyses_for_condition/1`, `store_analysis_response/1`, curation, `unusable_study_ids/1` |
| condition-seeded crawl (`condition_crawl_runs/attempt`, `ConditionCrawlWorker`, Entrez condition path) | admin acquisition of a condition's corpus |

**New (small, additive):**
- A read query `research_for_condition/1` returning studies+analyses already grouped/ordered by
  research type (thin wrapper over `analyses_for_condition/1` + a `study_design → bucket` mapper).
- A pure `ResearchType` mapper module (extractor `study_design` strings → the 7 buckets above).
- Condition autocomplete query over `Health.Condition` (name + translations).
- 1–2 nutritionist LiveViews (`NutritionistLive.Research{Search,Condition}`) + route under the
  existing `:nutritionist` live_session.

## 5a. Journal authority signal  ✅ DELIVERED 2026-10-26 (Phase 0b)

The nutritionist wanted a "which journal / how authoritative" axis beyond design + funding.

**Source decision — MEDLINE indexing, not SJR.** The design first named SCImago **SJR** (Q1–Q4), but
SJR data is **CC BY-NC** — not safe to bundle in a commercial product. Instead we use the
**MedlineCitation `@Status`** already present in the PubMed efetch XML we retain: a `"MEDLINE"`
status means the paper was curated into MEDLINE, i.e. it ran in a **MEDLINE-indexed** (vetted,
selective) journal. This is **public-domain, commercial-safe, and needs no bundled dataset**.
Coarser than quartiles, but honest. (JCR Impact Factor = Clarivate-licensed, SJR = CC BY-NC — both
rejected.)

Shipped:
- **Capture:** `entrez/client.ex` now parses `Article/Journal/ISSN` (+ `MedlineJournalInfo/ISSNLinking`)
  and the `MedlineCitation/@Status`, persisted as new additive columns `scientific_studies.issn` +
  `scientific_studies.citation_status`.
- **Backfill:** `Mehungry.Literature.backfill_journal_metadata/0` re-parses the retained
  `entrez_responses` payloads (`raw_json["raw_xml"]`) to populate the two columns on existing studies
  — **no re-crawl**. *(Run once after deploy.)*
- **Mapping:** pure `Mehungry.Literature.JournalAuthority` — `study|status → medline_indexed?` /
  `label/1` (`"MEDLINE-indexed"` or `nil`) / `rank/1` (0 indexed, 1 not). Extensible: a future DOAJ
  (vetted OA, CC0) or tier can fold in behind the same API. ISSN is captured now as the universal
  join key for any such dataset.
- **UX:** a "MEDLINE-indexed" chip on the result card, and the **secondary in-group sort** =
  MEDLINE-indexed first, then recency, then sample size.

**Follow-up (small, additive):** DOAJ "vetted open-access" badge from the bundled CC0 DOAJ ISSN list,
keyed on the ISSN we now capture.

## 6. Keep / Cut inventory (decommission-in-place)

### CUT — science *generation* machinery (remove routes/UI/workers; leave tables dormant for now)

**Contexts / core modules**
- `Chemistry.*` (PubChem resolver, `compound_sources`, `pubchem_responses`) — compound identity from mentions.
- `Literature.PubTator.*`, `study_entity_mention`, `study_entity_relation`, `annotation_run(s)`/`annotation_attempt`, `pubtator_responses`.
- `Literature.Entrez` **species/compound-seeded** crawl path + `crawl_run(s)`/`crawl_attempt` (species ledger). **Keep the condition path.**
- `Food.CompoundCandidates`, `Food.CompoundMeasurements`, `Food.EvidenceAggregation`, `Food.CompoundPlausibility`, `Food.SpeciesCompounds` **writers**, `species_search`, `ingredient_compound_summary`; tables `compound(_identifier/_translation/_measurement/_measurement_candidate)`, `species_compound_candidate(_study)`, `ingredient_compound_relationship`, `candidate_derivation_runs`.
- `Health.RecommendationCandidates`, `Health.ConditionRecCandidates`, `Health.ClaimRules`, `condition_rec_extraction_attempt`, `compound_recommendation_candidate(_study)`, `condition_recommendation_candidate(_study)`, `recommendation_derivation_run(s)`, `condition_state_recommendation(_study)`.
- Glycemic-index derivation path (`gi_candidates`).
- `Science.PipelineWatchdog` (trim to the condition-crawl topic only), `Science.PipelineReset`, `Science.RunReconciler` (trim).

**Oban workers (remove from queues/cron)**
`literature_crawl_worker` (species), `pubtator_annotation_worker`, `compound_candidate_derivation_worker`, `compound_fact_audit_worker`, `recommendation_candidate_derivation_worker`. **Keep** `condition_crawl_worker`, `pipeline_watchdog_worker` (trimmed).

**Admin LiveViews / routes (`/professional/**`)**
`SciencePipeline`, `Entities`, `CompoundCandidates`, `UsdaSchema` (species curation), `LiteratureRuns` (trim to condition), and the compound/recommendation half of `HealthConditions`. **Keep** `Studies` (research list) and a slimmed admin curation surface (condition crawl + analyze + claim `position`).

**REST seam (`/api/local_ai/*`)**
`PendingController`, `CandidatesController`, `GiCandidatesController`, `ConditionPendingController`, `ConditionRecCandidatesController` (phase-aware *recommendation* extraction). **Keep** `FullTextController` **only if** still used — confirm nothing else depends on it; the research `/analyze` ingestion is an *outbound* call from the admin LiveView, not this inbound seam, so the whole seam may be removable.

### KEEP — untouched
- All consumer advise reads: `Health.species_for_condition/2`, `recommendations_for_condition/2`, `nutrient_recommendations_for_condition/1`, `Food.recipes_with_badge/2`, `Food.NutrientClaims`, `NutrientTargets`, `NutrientRecommendation`, and the already-promoted `species_compound_relationship` facts they read.
- Meal blueprints, recipe badges + mobile `recipe_json`, `/foods` condition filter, AI-bot condition seeds, article references.
- The entire Food/Recipe/USDA-ingredient-seeding domain (USDA *ingredient* seeding ≠ USDA *species* curation).

## 7. Acquisition flow (curated catalog)

1. Admin picks/creates a `Health.Condition`.
2. Admin runs the **condition-seeded crawl** (`enqueue_condition_crawl`) → `ScientificStudy` + `StudyCondition`.
3. Admin runs the extractor `/analyze` over those PMIDs → `store_analysis_response` → `StudyAnalysis`
   (nutrition title-filter + nutrition vocabulary happen inside the extractor; abstract-only papers
   flagged `unusable`).
4. Admin curates claim `position` (hide `wrong`/`ingore`).
5. Nutritionists search the catalog; results are served entirely from already-stored rows (fast, offline-safe).

**Three ways to run steps 2–3** (all share one ingest core, `Literature.ResearchIngestion.analyze_condition/2`):
- **Per-condition, interactive** — the admin UI on `/professional/health` ("Search papers" → select → "Analyze selected").
- **Bulk, from the admin UI — the "Research ingestion" card on `/professional/health`** (✅ DELIVERED
  2026-10-27). The **production** control: a "Run ingestion" button (with *Crawl PubMed first* /
  *Re-analyze* toggles) **fans out one Oban job per condition**
  (`Mehungry.ObanWorkers.ResearchIngestionWorker`, `:imports` queue, concurrency 1 → still sequential
  over the one extractor), writing live progress to a `research_ingestion_runs` row shown on the page
  (status · conditions done/total · failed · current condition · stored counts). **Restart-safe** —
  because each condition is its own job, a server restart/deploy only interrupts the in-flight
  condition (rescued + retried by Oban `Lifeline`, `max_attempts: 3`); the rest resume on boot, and
  the run finalizes when every condition has reported. One run at a time
  (`ResearchIngestionRuns.enqueue/1` refuses a second); a **Cancel** button
  (`cancel_research_ingestion/0`) stops a run, and a mount-time reconcile
  (`reconcile_research_ingestion/0`) unwedges a run left `processing` by a crash. Idempotent — just
  run again to resume.
  - **Fail-fast feedback when the extractor link is down** (✅ 2026-10-27). "Run ingestion" first does
    a **pre-flight reachability probe** (`Mehungry.Extractor.reachable?/0` → `Extractor.Client.reachable?/0`,
    a 5 s GET to the configured base URL): a dead link flashes *"Extractor unreachable at <url> …"*
    immediately and **does not start the run** (no churning 3×N retries). And if a run does start but
    **every** condition fails (e.g. the service dies mid-run), `finalize/1` marks the run **`failed`**
    (red badge) rather than a misleading `completed` — partial failures still finalize `completed`
    with the `· N failed` count + error line visible. So an online admin sees the problem either at
    the click or on the live panel.
  > *History:* v1 (2026-10-27) used a **single** orchestrator job over all conditions; a server
  > restart mid-run left it orphaned in `executing` and the run stuck `processing` forever. Replaced
  > same-day by the per-condition fan-out above.
- **Bulk, offline — `mix research.ingest`** (✅ DELIVERED 2026-10-27). The same pass from the command
  line (dev/ops), for when a shell is available. Idempotent (skips already-analyzed + `unusable`);
  `--crawl` PubMed-crawls each condition first; `--force` re-analyzes (backfill `sections` onto
  pre-2026-10-27 analyses).

**Backfilling `sections` onto already-analyzed conditions** — a *normal* run skips every
already-analyzed paper, so pre-existing conditions won't gain the reader until re-analyzed with
**Re-analyze** / `--force`. Force re-sends open-access papers **and** `nil`/unknown-`source_type`
papers (those analyzed by an older extractor that didn't record the source — `target_pmids/2` treats
unknown as retryable, unlike the broad `unusable_study_ids/1`). It deliberately does **not** re-send
papers *known* to be `abstract`/`none` — they have no full text, so they can never get a section
outline or a reader link (expected). `source_type` is part of the analysis `content_hash`, so a
force run that newly resolves a paper's source persists it (no endless re-targeting).

      mix research.ingest                      # all conditions, analyze what isn't analyzed yet
      mix research.ingest "Ulcerative Colitis" # one condition
      mix research.ingest --crawl              # crawl each first, then analyze
      mix research.ingest --force              # re-analyze (backfill sections)

**Offline guarantee:** the extractor is touched **only** during acquisition (steps 2–3). Once stored,
the nutritionist search, grouped results, and full-text reader read **100% from the database**
(`conditions_with_research/1`, `grouped_research_for_condition/1`, `full_text_for_reader/1` — no
HTTP, no extractor), so the content is available per condition **always**, extractor up or down. The
slow Python extractor stays non-deployed; nutritionists never wait on it.

## 8. mehungry_extractor — one enrichment (sections); synthesis kept for later

`/analyze` already returns per-paper claims with spans, `study_design`, `sample_size`, funding. The
**section-outline reader** (above) needs the paper's structure, so the extractor's `/analyze`
per-paper `paper_claims[]` entry now also carries a compact **`sections`** outline (reusing the
canonical `Document.sections` it already builds — **no new NLP**; populated only for `open_access`
papers, `[]` otherwise). The Elixir side is tolerant of its absence (a not-yet-upgraded extractor
simply yields no reader link). **Cross-paper synthesis** (`/observe/synthesize` → `conclusions`) is
deliberately **kept** and is the natural **phase 2**: a "what the evidence says overall for this
condition" summary above the per-paper list (would need a new `ConditionSynthesis` store on the
Elixir side). Not in v1.

## 9. Phasing

- **Phase 0 — build the feature (additive, no deletions): ✅ DELIVERED 2026-10-26.** Nothing
  removed — zero risk to consumer features. Shipped:
  - `Mehungry.Literature.ResearchType` — pure extractor-`study_design` → evidence-hierarchy bucket mapper (+ unit test).
  - `Literature.conditions_for_search/1` (full condition list + fuzzy name search, research-first;
    backs the landing), `Literature.conditions_with_research/1` (with-research-only catalog, retained)
    and `Literature.grouped_research_for_condition/1` (grouped, evidence-ordered, recency/sample sorted
    within a bucket) in `StudyAnalyses`, delegated on the `Literature` facade (+ tests).
  - `MehungryWeb.NutritionistLive.ResearchSearch` (`/nutritionist/research`) — fuzzy condition search over
    the full condition list; `…ResearchCondition` (`/nutritionist/research/:condition_id`) — grouped result cards
    with publication metadata + highlighted claims (subject→predicate→object + verbatim evidence quote
    + PubMed source link); claims curated `wrong`/`ignore` are hidden (+ LiveView smoke tests).
  - Routes under the `:nutritionist` live_session + a "Research" nav entry in the nutritionist sidebar.
- **Phase 0b — journal authority (additive): ✅ DELIVERED 2026-10-26.** ISSN + MEDLINE-status
  capture, backfill from retained payloads, `JournalAuthority` mapper, authority chip + in-group
  sort (§5a). Public-domain MEDLINE signal (SJR dropped on licensing). Run
  `Mehungry.Literature.backfill_journal_metadata/0` once after deploy.
- **Phase 0c — results-page rework + in-app reader (additive): ✅ DELIVERED 2026-10-26.** Collapsible
  research-type groups; the result card now leads with a **section outline** (deep-links) for
  full-text papers and tucks the extracted claims behind a per-card "Suggested notes (N)" toggle
  (relabelled from "Show findings" in research_notes Phase 1, each note "Open in text" → reader); a new
  **reader** LiveView (`ResearchPaper`, `/nutritionist/research/:condition_id/paper/:study_id`)
  renders the paper's sections with `#sec-`/`#par-` anchors + inline `<mark>` claim highlighting.
  Backed by an additive `study_full_texts.sections` jsonb column, written from the enriched
  `/analyze` response (see §8), read via `Literature.full_text_for_reader/1` /
  `grouped_research_for_condition/1` (which now marks each paper's `has_full_text` + section
  `outline`). Requires the extractor's `sections` enrichment (§8) to light up; degrades gracefully
  without it.
- **Phase 1 — decommission generation machinery: ✅ DELIVERED 2026-10-26.** Reversible
  (contexts, Oban workers, schemas, and **tables all kept dormant** — nothing dropped). Removed:
  - **Admin UIs + routes** `/professional/{science, science/studies, science/entities, literature,
    compound-candidates}` and their LiveViews (`SciencePipeline`, `Studies`, `Entities`,
    `LiteratureRuns`, `CompoundCandidates`) + their tests + the matching sidebar nav links.
    *(Deviation from §6: `Studies`/`Entities` were cut too — their only entry point was the removed
    `SciencePipeline`, and they aren't needed for the feature. Trivially re-addable.)*
    **`UsdaSchema` (`/professional/usda-schema`) was kept** (restored after the initial cut): it
    curates `FoundementalFoodSpecies` (name + `scientific_name` + ingredient assignment) — a concept
    + dataset worth maintaining independently of the decommissioned species crawl that used to
    consume `scientific_name`. A new way to power it is TBD.
  - **The entire inbound `/api/local_ai/*` seam** — all six controllers (pending, full_text,
    candidates, gi_candidates, condition_pending, condition_recommendation_candidates), the scope, the
    `:local_ai_api` pipeline, and their tests. The research `/analyze` ingestion is an *outbound* call
    from `HealthConditions`, so nothing kept depends on the seam. (`RequireLocalAiToken` plug left
    dormant. The separate non-deployed `apps/mehungry_local_ai` app is now orphaned — left as-is.)
  - **Pipeline cron trimmed to condition-crawl only** — `PipelineWatchdog` + `RunReconciler` no longer
    resume/ reconcile species-crawl / PubTator-annotation / compound- & recommendation-candidate
    runs; condition-crawl (the research acquisition) still self-heals.
  - **Kept intact:** `HealthConditions` (`/professional/health`) — the admin acquisition + curation
    surface (per-condition crawl → analyze → claim curation). *Follow-up:* its compound/recommendation
    *review* sections are now dormant (no new candidates derived); slimming them into a focused
    research-acquisition page is a later, optional cleanup.
  - **Untouched:** all consumer advise reads (meal blueprints, recipe badges + mobile `recipe_json`,
    `/foods` condition filter, AI-bot condition seeds, article refs) and the research-search feature.
- **Phase 2 (later) — hard delete:** drop dormant tables + schema modules via migration once the
  new feature is proven and the dormant data confirmed unused.
- **Phase 3 (later) — synthesis:** cross-paper condition synthesis surface.

## 10. Docs to update (same-commit rule)
- `docs/features/professionals/` — new feature doc for the research search engine.
- `docs/implementation/science/*` — rewrite `science.md` / `scientific_pipeline.md` to the
  condition-seeded-only pipeline; delete/retire the compound-candidate/PubTator/chemistry docs in Phase 1.
- `docs/implementation/new_dec_specs/mobile_api_spec.md` — only if a `/api/local_ai/*` change or a
  mobile field is touched (should be none in Phase 0; `recipe_json` badges stay).
- `CLAUDE.md` context table — trim the science/Chemistry/Health rows in Phase 1.

## 11. Resolved open items (2026-10-26)
1. ✅ **"Direct link to the part" ceiling** — quoted sentence inline + article link + optional PMC
   section anchor. Accepted ("yes for now").
2. ✅ **Claim visibility** — show `food_related` + `general_science` + **un-curated** claims; hide
   only `wrong`/`ignore`. Admin can demote. ("ok")
3. ✅ **`/api/local_ai/*` removal** — verify `FullTextController` is unused by the research
   ingestion path (outbound call from the admin LiveView), then remove the inbound seam in Phase 1.
   ("yes")
4. ✅ **Journal authority signal — IN SCOPE** (not deferred). Designed in §5a (SJR, Phase 0b). ("yes")

### Remaining sub-item (not blocking Phase 0)
- **SJR redistribution terms** — verify SCImago's license permits bundling a snapshot in `priv/`
  (with attribution) before Phase 0b ships.
