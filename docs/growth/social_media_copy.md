# Social media copy — ready-to-post captions

**Purpose:** Hand-written, feature-surfacing captions for growth posts. Companion to
[growth_plan.md](growth_plan.md) (the *why/when*) and [social_publishing.md](social_publishing.md)
(the *how it ships*). Keep captions here so they're reusable and don't get re-invented per post.

**Audience reminder (from [app_status.md](../implementation/app_status.md)):** ~98% Greece, Crete-heavy →
**lead with the Greek version on Facebook** (the only live auto-publish channel today; Instagram
& Pinterest are disabled — see `social_publishing.md`). Value-first, not spam.

---

## Post: "AI meal plan from real user recipes"

**Hook:** the AI assistant builds a full week from *real, community-created recipes* — not generic
"100g chicken" robot plans. This is the actual differentiator.

### Greek (primary — post this on FB)

> **Ζήτησα από τον AI βοηθό του m3hungry να μου φτιάξει όλο το εβδομαδιαίο μου πρόγραμμα — και χρησιμοποίησε μόνο αληθινές συνταγές που μαγειρεύει ο κόσμος.** 🍳
>
> Όχι γενικά "100γρ κοτόπουλο, 50γρ ρύζι". Ο βοηθός πήρε πραγματικές συνταγές της κοινότητας, ισορρόπησε τα μακροθρεπτικά όλης της εβδομάδας και μου έδωσε:
>
> ✅ Πλήρες πρόγραμμα 7 ημερών (πρωινό → βραδινό + σνακ)
> 🥗 Αυτόματο υπολογισμό διατροφικής αξίας — πρωτεΐνη, υδατάνθρακες, λιπαρά ανά μέρα
> 🛒 Έτοιμη λίστα για ψώνια για όλη την εβδομάδα
> 🇬🇷 Όλα στα Ελληνικά
>
> Μου πήρε περίπου 2 λεπτά. Δες την εβδομάδα 👇
>
> Δοκίμασέ το δωρεάν → [share link]
>
> #εβδομαδιαιοπρογραμμα #μεσογειακηδιατροφη #διατροφη #mealprep #m3hungry

### English

> **I asked m3hungry's AI to plan my whole week — and it only used real recipes people actually cooked.** 🍳
>
> No generic "100g chicken, 50g rice" robot plans. The assistant pulled from real, community-created recipes, balanced the macros across the week, and handed me:
>
> ✅ A full 7-day meal plan (breakfast → dinner + snacks)
> 🥗 Nutrition worked out automatically — protein, carbs, fat per day, with badges like "High in Protein" / "Source of Fiber"
> 🛒 A ready-to-go shopping list for the week
> 🇬🇷 All of it in Greek (or English)
>
> Built it in about 2 minutes. Here's the week 👇
>
> Try it free → [share link]
>
> #mealplan #mediterraneandiet #mealprep #healthyeating #m3hungry

### Short variant (IG/Pinterest caption, when re-enabled)

> One prompt → a full week of meals built from real recipes, balanced macros, and a shopping list ready to go. In Greek. In 2 minutes. 🇬🇷🥗 Try it free → [link]

### Features surfaced (all real — do not overclaim)

| Feature | Backed by |
|---|---|
| AI plans from **real user recipes** | `AI.Agents.MealPlanAgent` over community recipes — the differentiator |
| Auto nutrition + per-serving badges ("High in Protein", "Source of Fiber") | `Food.NutrientClaims` (EU Reg 1169/2011 NRV badges) |
| Auto shopping list | `Inventory` basket |
| Greek-first / bilingual | `Languages` + locale-prefixed URLs |
| Speed ("2 minutes") | the Week-3 activation framing in `growth_plan.md` |

**Off-limits:** no health-condition / medical-benefit claims. Condition-targeted advice is
non-public (YMYL / SaMD) per `CLAUDE.md` and `docs/seo.md`.

### Posting checklist (per growth_plan.md)

- [ ] Link to a **specific `/meal-plans/:slug`**, not the homepage (carries OG unfurl meta +
      "Made with m3hungry" referral footer). QR/share-landing rule, Week 2.
- [ ] Attach the week's **share card image** (`og_image_url` — real macro donut) so FB unfurls richly.
- [ ] Post Greek version first on the live Facebook Page.
- [ ] Value-first tone; no spam in Greek cooking groups / r/greece.
