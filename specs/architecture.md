# Architecture - Branded Deck Generator

## Modules

- `src/shared/schemas/` - Zod schemas and types (DeckJSON, BrandProfile, TextWithHighlight, BodyBlock, Callout). Pure, no I/O.
- `src/shared/config/` - Format registry, constants. Pure data.
- `src/shared/layouts/` - Layout registry (register, lookup, validate). No rendering.
- `src/shared/brand-profiles/` - Hardcoded brand data objects.
- `src/renderer/` - ThemeProvider, SlideWrapper, DeckRenderer, primitives. React rendering only.
- `src/layouts/` - Individual layout components (title-slide, single-column, etc.). Each = schema.ts + Component.tsx + index.ts.
- `src/server/` - Hono API server, routes, agent loop. HTTP/IO boundary.
- `src/pages/` - Frontend React pages (chat UI, preview, render route).
- `src/components/` - Shared UI components (ChatPanel, SlidePreview, etc.).
- `src/hooks/` - React hooks. `src/styles/` - CSS globals, font imports. `src/test-utils/` - Test harness utilities.

## Dependency Rules

- `shared/` must not import from `renderer/`, `layouts/`, `server/`, `pages/`, `components/`
- `renderer/` can import from `shared/`. Must not import from `server/`, `pages/`, `layouts/`
- `layouts/` can import from `shared/` and `renderer/primitives/`. Must not import from `server/`, `pages/`
- `server/` can import from `shared/`. Must not import from `renderer/` or `layouts/` (except SSR entry point)
- `pages/` and `components/` can import from `shared/`, `renderer/`, `layouts/`

## Hard Constraints

- Agent produces only DeckJSON/DeckDiff — never JSX, React components, or CSS
- All theming via CSS custom properties — zero hex literals in layout component files
- Each layout = exactly 3 files: schema.ts, Component.tsx, index.ts. No other files change to add a layout.
- Bun is the runtime and package manager everywhere — no npm, no yarn, no Node.js
- All external API calls injected via AgentProvider interface, never module-level singletons
