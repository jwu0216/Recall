# Recall — Product decisions

## V1 (building now)

- **Scope:** Share (links, images, PDFs, text) + Ask (natural-language search with citations) + Library + Settings
- **AI:** User pastes their own OpenAI API key (dev / TestFlight). Subscription comes later for public launch.
- **Out of V1:** Full Photo Library indexing, backend billing, multi-turn chat product, widgets/Siri

## V2 Photos — cost rules (locked)

Photos indexing is deferred. When we build it:

1. **Opt-in only** — never auto-index on install
2. **Low-detail vision by default** — high detail is an explicit user choice
3. **OCR-first** — on-device Vision OCR before OpenAI vision
4. **Estimate before index** — show photo count + rough cost; require confirm
5. **Batch + pause** — chunked processing; pause anytime
6. **Skip Hidden** by default; optional Skip Screenshots
7. **Never reprocess** unchanged photos (keyed by `localIdentifier`)
8. **Quotas** once Recall pays for AI (Free/Paid caps)

Rough cost ballpark with low-detail `gpt-4o-mini` vision: often about **$2–8** for a one-time pass over 5k–20k photos. High detail without caps can run to tens of dollars.

## Later (public ship)

- Your backend + OpenAI key
- Free tier + subscription
- App Store privacy policy
- Photos V2 behind the cost rules above
