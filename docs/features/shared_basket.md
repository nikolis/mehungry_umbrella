# Shared shopping lists

The owner of a shopping list invites other people to it. Everyone on the list sees
the same items, adds to it and ticks things off, live, on web and mobile.

**Why it exists (mission fit).** The person who shops and cooks for a diet-watcher is
often a partner, parent or carer, not the patient. A list built from the calendar
week or from a nutritionist's plan is only useful if it reaches whoever is standing
in the shop. Sharing the list gets the plan into the household. It is a second-ring
consumer feature, and every invitation to a non-user is also a signup.

Implementation: [`../implementation/inventory_basket.md`](../implementation/inventory_basket.md)
(§ Sharing). Mobile contract: `mobile_api_spec.md` §10.1 and the `basket:<id>` channel (§13).

---

## Rules

| Topic | Rule |
|---|---|
| Unit of sharing | One list at a time. A user keeps private lists alongside shared ones; there is no "household" that shares everything. |
| Roles | **Owner** (who created the list) and **member**. No view-only role. |
| Members can | See the list, add / edit / tick off / delete items, import a recipe or a meal into it, leave. |
| Only the owner can | Rename or delete the list, rebuild it from a calendar week, invite, revoke an invitation, remove a member. |
| Size | At most 6 people per list (owner included) and 10 unanswered invitations per list. |
| Who can invite | The owner, with a confirmed email. Rate-limited to 20 invitations an hour per inviter. |
| Price | Free on every tier. |

## Inviting

The owner opens **Share** on a list and either types an email or leaves it empty.

- **With an email** the invitation link is emailed to that address. If the address
  belongs to an existing account, that person also gets an in-app notification and
  sees the invitation at the top of `/basket` with **Join** / **Decline**.
- **Without an email** the owner gets a link to send however they like (chat, SMS).

Either way the result is a **single-use link that expires after 7 days**. The link is
shown once, when it is created — only its hash is stored — so the owner copies it
then. Pending invitations are listed in the Share panel and can be revoked.

Whoever is signed in when the link is opened is the one who joins. Someone without an
account is sent to log in or sign up first and then returned to the invitation.

**Why a link and not a user search.** The people a grocery list is shared with are
usually household members who have no account yet, and the follow graph points at
recipe creators, not at family. A global user search would also make every account
discoverable on a platform many people use for a medical reason, and would let anyone
send invitations to strangers. A link only reaches someone the owner can already
message.

## What the invitee sees

Before accepting: the inviter's name and the list's title. Never its contents.
Declining is silent — the inviter is not told. After accepting, the owner gets a
"joined your list" notification.

## Privacy and safety

- People on a list see each other's **display name and avatar only**, never an email.
- The invite form answers the same way whether or not the email is registered, so it
  cannot be used to find out who has an account.
- **Blocks.** If either person has blocked the other, an invitation between them is
  not delivered (no notification, no email) and its link does not work for that
  person. Blocking someone also removes each of you from any list the other owns.
- An invitation link is a bearer token: whoever holds it can join. That is why it is
  single-use and short-lived, and why the owner sees everyone on the list and can
  remove them.

## Working on a shared list

- **Live.** A change made by anyone appears for everyone else with the list open,
  without a reload. A member who is removed while viewing is moved to another of
  their lists and told the list is no longer available.
- **Attribution.** On a shared list each line shows who added it and, once ticked,
  who bought it ("added by Maria · bought by you"). Someone who has since left the
  list is not named.
- **Two people at once.** Ticking a line sets it to ticked rather than flipping it,
  so two shoppers ticking the same line both leave it ticked. Editing is
  last-write-wins. Acting on a line someone else just deleted does nothing.

## Leaving, removing, deleting

- A member can **leave** at any time (sidebar or Share panel).
- The owner can **remove** a member.
- The owner **deleting** a shared list deletes it for everyone; the confirmation says
  how many other people will lose it.
- If the owner **deletes their account**, a shared list is handed to its
  longest-standing member instead of disappearing. The owner's unshared lists are
  deleted with the account, as before.

## Week lists

A list built from a calendar week ("Shopping list for the week") holds the **owner's**
meals for that week. Sharing it works like any other list; a member can add their own
meals to it with the meal import.

## Not in this version

A view-only role, handing ownership to someone by choice, comments on a line,
assigning a line to a person, and inviting by picking from followers.
