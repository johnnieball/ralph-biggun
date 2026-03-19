# Static Site Generator ("Beast")

Build a static site generator in TypeScript (Bun runtime, Vitest tests) that takes structured JSON content, validates it, renders it through templates with theming, and outputs styled HTML pages with optional PDF export.

## Content Model

Pages are defined as JSON files with an id, title, layout type, metadata (author, date, tags), and content. The layout determines the content shape:

- **article**: has a body (markdown) and summary
- **listing**: has an array of items, each with title, description, and optional link to another page
- **profile**: has a name, bio (markdown), and skills list

Use Zod for schema validation. The schema should use a discriminated union on the layout field.

## Validation

Single-page validation: ensure all required fields are present, content matches its layout type.

Multi-page (site) validation: check for duplicate page IDs, broken internal links (page references a non-existent ID), return ALL errors at once (not just the first). Errors should include the page ID and field path.

## File Loading

Load .json page files from a source directory. Skip non-.json files. Handle missing directories. Return partial results — valid pages plus a list of errors, so one bad file doesn't block the whole build.

## Template Engine

Render pages to complete HTML documents (doctype, head, body). Each layout type has its own rendering:

- Articles: title in h1, body rendered from markdown to HTML (headings, paragraphs, bold, italic, links, code blocks), metadata (author, date, tags), summary in meta description
- Listings: items as cards with titles and descriptions, optional links to other pages
- Profiles: name in h1, bio as markdown, skills as ul/li list

Title tag format: "Page Title | Site Title"

The HTML shell (doctype, head, body structure) should be shared across layouts, not duplicated.

## Theming

CSS theming via custom properties. A ThemeConfig has: primary/secondary/accent/background/text colours, heading and body fonts, spacing unit. Injected as a `<style>` tag with CSS custom properties. Base styles reference the custom properties. No theme = no style tag. All layouts use the same theme.

## Build Pipeline

Orchestrate the full flow: load pages → validate → render with theme → write HTML files to output directory. Each page becomes {pageId}.html. Create output dir if needed, clear it if it exists. Generate an index.html linking to all pages. Return a BuildResult with page count, errors, and output path. Partial success — valid pages build even if some fail validation.

## PDF Export

Optional PDF generation using Puppeteer (headless browser). The PDF renderer should be injected as a dependency. A4 format, 20mm margins. Handle Puppeteer not being installed gracefully. PDF failures for individual pages shouldn't crash the build. The build pipeline gains a pdf option to enable/disable it.

## CLI

Command-line interface:

- `bun run build-site --source ./content --output ./dist`
- `--theme path/to/theme.json` (optional)
- `--pdf` flag for PDF export
- Print summary on success, errors with file/field info on failure
- Parse args without external dependencies

## Watch Mode

`--watch` flag for development. Rebuild when .json files in source dir change. Incremental — only re-validate and re-render changed files. Show which files changed. Clean up file watcher on Ctrl+C. The watcher should be injected as a dependency for testability.

## Navigation

Every page gets a nav bar linking to all other pages. Current page highlighted with aria-current="page". Pages ordered by an optional priority field (lower = higher priority, default 999). Adding priority to the schema shouldn't break existing pages.

## Asset Fingerprinting

CSS written to a separate file with a content hash in the filename (styles.{hash}.css) for cache busting. HTML references it via link tag instead of inline style. Same theme = same hash. Changed theme = new hash + cleanup of old file.

## Logging

Structured logging for the build pipeline. Logger interface with events that have timestamp, level (info/warn/error), phase (load/validate/render/export/write), message, and optional metadata. ConsoleLogger and FileLogger implementations. No logger = no logging (null object pattern, no if-checks). Logging failures never crash the build.

## Data Tables

Article content can include data tables. Schema gains an optional tables array (id, caption, headers, rows). Body text references tables with {{table:tableId}} marker syntax. Rendered as HTML tables with caption, thead, tbody. Styled by theme. Non-existent table reference shows a visible error, not silent failure.

## Plugin System

Content transformation plugins that run after markdown rendering but before final HTML assembly. Plugin interface: transform(html, page, context). Plugins execute in order, piped. Built-in TablePlugin (refactored from the table marker logic) and HighlightPlugin (wraps ==text== in mark tags). Plugin errors are caught and logged, untransformed HTML used as fallback. Plugins only apply to layouts with body text.

## Search Index

Build generates a search-index.json with entries per page: id, title, url, excerpt (first 200 chars of plain text), tags. HTML tags stripped before truncation. Listing pages use first item's description, profiles use bio. Only generated if there's at least one page.

## Config File

site.config.json for site settings: title, base URL, source/output dirs, theme (inline or path), pdf toggle, active plugins. CLI gains --config flag. CLI flags override config values. Missing config without --config is fine; missing config WITH --config is an error.

## Typed Generics

Page type uses TypeScript generics: Page<L extends Layout> where L determines content type. parsePage returns a discriminated union. renderPage uses type narrowing. Generic types flow through the whole pipeline without any `as any` or `as unknown` casts. Backward compatible with existing unparameterised Page type.
