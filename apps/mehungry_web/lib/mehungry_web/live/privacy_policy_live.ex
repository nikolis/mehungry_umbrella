defmodule MehungryWeb.PrivacyPolicyLive do
  use MehungryWeb, :live_view

  # NOTE FOR THE OPERATOR: this is a GDPR Art. 13/14 privacy notice drafted from
  # the codebase (operator details filled: Nikolaos Galerakis, Greece). It should
  # still be reviewed by a qualified data-protection lawyer before being relied
  # upon in production, and the substantive risks (health claims, Art. 9 basis,
  # erasure cascade) in docs/legal/legal_review_2026-10.md remain open.
  # See also docs/audit/03-eu-compliance-risk-register.md.

  @last_updated "13 October 2026"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, last_updated: @last_updated)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-ink text-parchment">
      <div class="mx-auto max-w-3xl px-6 py-16">
        <p class="text-sm font-semibold uppercase tracking-wider text-paprika">Legal</p>
        <h1 class="mt-2 font-display text-4xl leading-tight text-parchment">Privacy Policy</h1>
        <p class="mt-3 text-sm text-parchment-dim">
          Last updated: {@last_updated}
        </p>
        <nav class="mt-4 flex flex-wrap gap-x-4 gap-y-1 text-sm" aria-label="Legal documents">
          <a href="/terms" class="text-paprika underline-offset-2 hover:underline">Terms of Service</a>
          <a href="/cookies" class="text-paprika underline-offset-2 hover:underline">Cookie Policy</a>
          <a href="/legal" class="text-paprika underline-offset-2 hover:underline">Legal Notice</a>
        </nav>

        <div class="mt-8 rounded-xl border border-ink-panel2 bg-ink-panel p-5 text-sm leading-relaxed text-parchment-dim">
          This notice explains what personal data M3Hungry collects, why, who we share it with,
          how long we keep it, and the rights you have under the EU General Data Protection
          Regulation (GDPR). M3Hungry is a food, recipe and nutrition platform. Some features
          (health-condition badges, nutritionist records) involve
          <strong class="text-parchment">health data</strong>, which we treat with extra care — see
          <a href="#health-data" class="text-paprika hover:underline">section 4</a>.
        </div>

        <.toc entries={[
          {"who-we-are", "1. Who we are (data controller)"},
          {"data-we-collect", "2. What data we collect"},
          {"why-and-legal-basis", "3. Why we use it & legal bases"},
          {"health-data", "4. Health data (special category)"},
          {"sharing", "5. Who we share data with"},
          {"transfers", "6. International transfers"},
          {"retention", "7. How long we keep data"},
          {"your-rights", "8. Your rights"},
          {"ai", "9. Automated processing & AI"},
          {"cookies", "10. Cookies & analytics"},
          {"children", "11. Children"},
          {"changes", "12. Changes to this notice"},
          {"contact", "13. How to contact us / complain"}
        ]} />

        <.section id="who-we-are" title="1. Who we are (data controller)">
          <p>
            The controller responsible for your personal data is the individual sole trader
            operating M3Hungry:
          </p>
          <ul class="mt-3 list-none space-y-1 rounded-lg border border-ink-panel2 bg-ink-panel px-4 py-3 text-parchment">
            <li><span class="text-parchment-dim">Operator:</span> Nikolaos Galerakis</li>
            <li><span class="text-parchment-dim">Address:</span> Kalonykti, Greece</li>
            <li>
              <span class="text-parchment-dim">Contact:</span>
              <a href="mailto:nikolisgal@gmail.com" class="text-paprika hover:underline">nikolisgal@gmail.com</a>
            </li>
          </ul>
          <p class="mt-3">
            For some features we act jointly with, or on behalf of, other parties — most notably
            nutritionists who keep client records on the platform (see
            <a href="#health-data" class="text-paprika hover:underline">section 4</a>).
          </p>
        </.section>

        <.section id="data-we-collect" title="2. What data we collect">
          <p>Depending on how you use M3Hungry, we may process:</p>
          <.data_table rows={[
            {"Account data", "Email, password (hashed), display name, and — if you sign in with Facebook, Google or Instagram — the basic profile fields that provider returns."},
            {"Profile & preferences", "Dietary preferences, diet type, survey answers, daily calorie target, and any health-condition badges you choose to opt into."},
            {"Content you create", "Recipes, comments, votes, posts, meal plans, shopping baskets, images and media you upload."},
            {"Nutritionist client records", "If you are (or are a client of) a nutritionist: intake data such as height, weight, BMI/BMR/TDEE, goals, free-text notes and consultation notes."},
            {"Payment data", "Subscription tier and billing status. Card details are handled directly by Stripe — we do not store full card numbers."},
            {"Usage & device data", "If you accept analytics cookies, Google Analytics processes usage data (pages visited, referrer, approximate location, device/browser type). We ourselves keep only an anonymous daily session counter that stores no IP, cookie or identifier."}
          ]} />
        </.section>

        <.section id="why-and-legal-basis" title="3. Why we use it & legal bases">
          <p>We only process personal data where we have a legal basis under GDPR Art. 6:</p>
          <.data_table rows={[
            {"Provide the service", "Performance of our contract with you (Art. 6(1)(b)) — accounts, recipes, meal plans, baskets, subscriptions."},
            {"Keep the service secure", "Legitimate interests (Art. 6(1)(f)) — fraud/abuse prevention, request-forgery protection, rate limiting."},
            {"Analytics & improvement", "Your consent (Art. 6(1)(a)) — collected via the cookie banner; you can withdraw it at any time."},
            {"Health-condition features & nutritionist records", "Your explicit consent (Art. 9(2)(a)) and/or provision of health care (Art. 9(2)(h)) — see section 4."},
            {"Marketing / beta invitations", "Your consent (Art. 6(1)(a)) — e.g. the trial/beta signup; you can unsubscribe from every email."},
            {"Legal obligations", "Compliance with law (Art. 6(1)(c)) — e.g. tax and accounting records for paid subscriptions."}
          ]} />
        </.section>

        <.section id="health-data" title="4. Health data (special category)">
          <p>
            Health-condition badges and nutritionist client records are
            <strong class="text-parchment">"data concerning health"</strong> — a special category
            under GDPR Art. 9, which is protected more strictly.
          </p>
          <ul class="mt-3 list-disc space-y-2 pl-5">
            <li>
              We process it only with your <strong class="text-parchment">explicit consent</strong>,
              or where it is necessary for the provision of care by a nutritionist you have engaged.
            </li>
            <li>
              You can withdraw that consent at any time; doing so stops future processing and you can
              delete the associated data (see <a href="#your-rights" class="text-paprika hover:underline">section 8</a>).
            </li>
            <li>
              Condition-related information on M3Hungry is general nutritional information, not medical
              advice, diagnosis or treatment. See the health disclaimer in our
              <a href="/terms" class="text-paprika hover:underline">Terms of Service</a>.
            </li>
          </ul>
        </.section>

        <.section id="sharing" title="5. Who we share data with">
          <p>
            We do <strong class="text-parchment">not sell</strong> your personal data. We share it
            only with the service providers ("sub-processors") that run the platform, each under a
            data-processing agreement and only as needed to deliver the service:
          </p>
          <.data_table rows={[
            {"Stripe", "Payment processing and subscription billing."},
            {"Supabase", "Object/media storage (images and uploads)."},
            {"Amazon Web Services (AWS)", "Hosting-adjacent infrastructure and the USDA seed-data import bucket."},
            {"Anthropic", "AI generation (recipes, meal plans, assistant features)."},
            {"OpenAI", "AI embeddings and cover-image generation (optional features)."},
            {"Google", "Sign-in (OAuth) and Google Analytics 4 (only after you accept analytics cookies)."},
            {"Meta (Facebook / Instagram)", "Sign-in (OAuth) and, if you choose, social-media publishing integrations."},
            {"Pinterest", "Social-media publishing integration (only if you connect it)."},
            {"Cloudflare Turnstile", "Bot/abuse protection on sign-up forms."}
          ]} />
          <p class="mt-3">
            We may also disclose data where required by law, or to protect our rights, users or the
            public. A current list of sub-processors is maintained in our
            <a href="/legal" class="text-paprika hover:underline">Legal Notice</a>.
          </p>
        </.section>

        <.section id="transfers" title="6. International transfers">
          <p>
            Several of the providers above (Stripe, Anthropic, OpenAI, Google, Meta, AWS) are
            established in, or process data in, the United States. Where personal data leaves the
            European Economic Area, we rely on an appropriate GDPR Chapter V safeguard — the
            EU–US Data Privacy Framework where the provider is certified, or EU Standard Contractual
            Clauses together with a transfer risk assessment.
          </p>
        </.section>

        <.section id="retention" title="7. How long we keep data">
          <ul class="list-disc space-y-2 pl-5">
            <li>Account and content data: for as long as your account is active.</li>
            <li>Analytics: handled by Google Analytics under its own retention; we keep only an anonymous, non-identifying daily session counter.</li>
            <li>Billing and tax records: as required by applicable accounting/tax law.</li>
            <li>
              When you delete your account, we delete or anonymise the personal data associated with
              it, except where we must retain certain records by law.
            </li>
          </ul>
        </.section>

        <.section id="your-rights" title="8. Your rights">
          <p>Under GDPR you have the right to:</p>
          <ul class="mt-3 list-disc space-y-2 pl-5">
            <li><strong class="text-parchment">Access</strong> — a copy of the data we hold about you.</li>
            <li><strong class="text-parchment">Rectification</strong> — correct inaccurate data.</li>
            <li><strong class="text-parchment">Erasure</strong> — delete your account and associated data.</li>
            <li><strong class="text-parchment">Portability</strong> — receive your data in a portable format.</li>
            <li><strong class="text-parchment">Restriction / objection</strong> — limit or object to certain processing.</li>
            <li><strong class="text-parchment">Withdraw consent</strong> — at any time, without affecting prior lawful processing.</li>
          </ul>
          <p class="mt-3">
            You can manage your profile and delete your account from your account settings, or contact
            us (<a href="#contact" class="text-paprika hover:underline">section 13</a>) to exercise any
            right. We respond within one month.
          </p>
        </.section>

        <.section id="ai" title="9. Automated processing & AI">
          <p>
            M3Hungry uses AI to generate recipes, meal plans, images and assistant responses, and to
            power nutrition features. Content that is AI-generated is produced by automated systems and
            may contain errors; it is informational and is not a substitute for professional advice.
            We do not use your personal data to make decisions that produce legal or similarly
            significant effects about you without a lawful basis and appropriate safeguards.
          </p>
        </.section>

        <.section id="cookies" title="10. Cookies & analytics">
          <p>
            We use strictly necessary cookies to keep you logged in and secure, and — only with your
            consent — Google Analytics to understand how the site is used. Full details, and the
            controls to withdraw consent, are in our
            <a href="/cookies" class="text-paprika hover:underline">Cookie Policy</a>.
          </p>
        </.section>

        <.section id="children" title="11. Children">
          <p>
            M3Hungry is not directed at children. You must be at least 16 (or the minimum digital-consent
            age in your country) to create an account. We do not knowingly collect data from children
            below that age.
          </p>
        </.section>

        <.section id="changes" title="12. Changes to this notice">
          <p>
            We may update this notice as the service evolves or the law changes. We will update the
            "last updated" date above and, for material changes, notify you through the app or by email.
          </p>
        </.section>

        <.section id="contact" title="13. How to contact us / complain">
          <p>
            For any privacy question or to exercise your rights, contact
            <a href="mailto:nikolisgal@gmail.com" class="text-paprika hover:underline">nikolisgal@gmail.com</a>.
            You also have the right to lodge a complaint with your national data-protection authority —
            in our case the Hellenic Data Protection Authority (HDPA, <span class="whitespace-nowrap">www.dpa.gr</span>) —
            if you believe we have not handled your data lawfully.
          </p>
        </.section>
      </div>
    </div>
    """
  end

  # --- view helpers --------------------------------------------------------

  attr :entries, :list, required: true

  defp toc(assigns) do
    ~H"""
    <nav
      class="mt-8 rounded-xl border border-ink-panel2 bg-ink-panel/60 p-5"
      aria-label="Table of contents"
    >
      <p class="mb-2 text-xs font-semibold uppercase tracking-wider text-parchment-dim">Contents</p>
      <ol class="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
        <li :for={{id, label} <- @entries}>
          <a href={"#" <> id} class="text-parchment-dim transition-colors hover:text-paprika">
            {label}
          </a>
        </li>
      </ol>
    </nav>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section id={@id} class="mt-10 scroll-mt-6">
      <h2 class="font-display text-2xl text-parchment">{@title}</h2>
      <div class="mt-3 space-y-3 leading-relaxed text-parchment-dim">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :rows, :list, required: true

  defp data_table(assigns) do
    ~H"""
    <div class="mt-3 overflow-x-auto">
      <table class="w-full border-collapse text-sm">
        <tbody>
          <tr :for={{label, desc} <- @rows} class="border-b border-ink-panel2 align-top">
            <td class="w-1/3 py-3 pr-4 font-medium text-parchment">{label}</td>
            <td class="py-3 text-parchment-dim">{desc}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
