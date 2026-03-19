# The Technologist — Personal News Reader

## What This Is

A personal, single-user news reader PWA that aggregates content from RSS feeds and displays it through an AI editorial layer. Claude processes ingested articles and produces a curated daily briefing plus a categorised feed, written in a consistent editorial voice.

Reading only — no audio, no video.

## Tech Stack

- **Runtime**: Bun
- **Language**: TypeScript (strict)
- **Framework**: Hono (API) + vanilla HTML/CSS/JS frontend (no React)
- **Database**: SQLite via Drizzle ORM
- **AI**: Anthropic Claude API for editorial processing
- **Testing**: Vitest

## Architecture

### Ingestion Layer

A single RSS/Atom feed worker. Configured with a list of feed URLs. Polls on a schedule, parses entries, deduplicates by content hash, and writes to a `raw_content` table.

Each raw content row has: id, source_name, source_url, title, body_text, published_at, content_hash, processed (boolean).

### Editorial Layer

Runs as a triggered job (API endpoint, not cron — keeps it testable).

Process:

1. Query all `raw_content` where `processed = false`
2. Send to Claude with an editorial system prompt
3. Claude returns structured JSON:
   - `daily_brief`: array of 5-6 items with rewritten headline, summary (80-120 words), importance_score (1-10), category
   - `categorised_feed`: remaining items with headline, summary (40-60 words), category, importance_score
4. Write results to `articles` table and `editions` table
5. Mark processed rows

Categories: AI & Tech, Business, Science, General (configurable via a config file).

### Presentation Layer

Server-rendered HTML pages served by Hono. No SPA — each route returns full HTML. Minimal client-side JS for bookmarking and pull-to-refresh.

## Database Schema

```
raw_content: id, source_name, source_url, title, body_text, published_at, content_hash, processed, ingested_at
articles: id, raw_content_id, headline, summary, body, category, importance_score, source_name, source_url, published_at, is_brief, created_at
editions: id, edition_date (unique), brief_article_ids (JSON array), generated_at
bookmarks: id, article_id, bookmarked_at
```

## UI Screens

### Today (/)

The landing page. Two sections:

1. **Daily Brief** — horizontal scrolling cards showing the 5-6 brief items. Each card: headline, source name, elapsed time ("2h", "1d"). Cards link to article detail.

2. **Feed** — vertical list of remaining articles grouped by category. Each category has a header and article rows showing: headline, summary (2 lines max), source, elapsed time. Sorted by importance_score descending.

### Article Detail (/article/:id)

Full article view: headline, source + date, body text, back link. Bookmark button (toggle). If the article is a brief item, show prev/next links to adjacent brief articles.

### Category Feed (/category/:slug)

Articles filtered to one category. Same list layout as the Today feed but single-category. Last 7 days only.

### Saved (/saved)

Bookmarked articles in a list, ordered by bookmark date descending. Each item has a remove-bookmark action.

## API Routes

```
GET  /api/brief/today           — today's edition with brief articles
GET  /api/articles?category=&limit=&offset=  — paginated feed
GET  /api/articles/:id          — single article
POST /api/bookmarks             — { articleId } → create bookmark
DELETE /api/bookmarks/:articleId — remove bookmark
GET  /api/bookmarks             — list bookmarks
POST /api/ingest/trigger        — manually trigger RSS ingestion
POST /api/editorial/trigger     — manually trigger editorial run
```

## Design

Clean, minimal, newspaper-inspired. Serif font for headlines and body (system serif stack). Sans-serif for UI elements (system sans stack). White background, dark text, red accent colour (#E3120B) for category headers and active states. 1px light borders between list items.

## Build Scope

Phase 1 — the Ralph build target:

1. Project scaffolding (Bun, TypeScript, Hono, Drizzle, Vitest)
2. Full database schema + migrations
3. RSS feed worker (fetch, parse, deduplicate, store)
4. Editorial engine (Claude API integration, structured output)
5. All API routes
6. All UI screens with server-rendered HTML
7. Bookmark toggle
8. Seed script with 20 mock articles across categories + a mock edition

Explicitly excluded: PWA/service worker, offline mode, pull-to-refresh, cron scheduling, image handling.
