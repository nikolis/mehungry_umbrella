# Features

Functional features — the value we deliver to customers (nutritionists + normal
users). These docs describe *what* the product does for people and the principles
behind it. How it's built lives in [`../implementation/`](../implementation/);
how it's surfaced lives in [`../growth/`](../growth/).

- [`product_foundation.md`](product_foundation.md) — **start here.** Purpose, audience, positioning, non-negotiable principles.
- [`normal_user.md`](normal_user.md) — consumer persona and journey.
- [`nutritionist.md`](nutritionist.md) — professional-nutritionist persona, the product's lead audience.
- [`meal_blueprints.md`](meal_blueprints.md) · [`meal_blueprints_diet_pattern_accuracy.md`](meal_blueprints_diet_pattern_accuracy.md) — meal-plan drafting feature.
- [`subscriptions_billing.md`](subscriptions_billing.md) — tiers and pricing (customer-facing; Stripe mechanics are detailed in `../implementation/professionals/payments/`).

## professionals/
Feature intent for the nutritionist workspace. Mechanics (payments, integrations,
status) are in [`../implementation/professionals/`](../implementation/professionals/).

- [`professional_profiles.md`](professionals/professional_profiles.md)
- [`appointments_booking.md`](professionals/appointments_booking.md)
- [`articles.md`](professionals/articles.md)
- [`client_records.md`](professionals/client_records.md)
