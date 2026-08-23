# Glycemic Index — no dataset drop (retired)

**This directory is no longer an ingest path.** The CSV-ingest of the compiled
International Tables was retired — that compilation isn't licensable for commercial use.

GI values are now **re-derived from primary literature** (path B): the Entrez crawl
discovers GI feeding-trial studies (`scientific_name × "glycemic index"`), the
non-deployed local-AI service extracts the measured value from each paper, and each
finding is fanned over the species as a review-gated candidate at
`/professional/glycemic-index`.

See **`docs/science/glycemic_index_licensing.md`** for the rationale and pipeline, and
`docs/science/glycemic_index.md` for the mechanics. The published PDFs live git-ignored
under `studies/` and are used **only** as an internal verification oracle
(`mix gi.verify`), never as a data source.
