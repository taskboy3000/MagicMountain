# Template.pm — HTML Template + CSS Boundary Rules

> Templates render data from the stash into HTML. They MUST NOT contain
> game logic, URL construction, or state computation. CSS defines the
> visual language through composable classes, not inline styles.

## Responsibilities
- Iterate stash variables and render HTML
- Use semantic heading tags (`<h2>`–`<h5>`) for all headings
- Use composable `mm-*` CSS classes for styling
- Keep inline `style=` attributes to data-driven values only

## Constraints (MUST NOT)
- NEVER hardcode `font-size`, `margin`, `padding`, or `cursor` as inline
  styles — use utility classes (`.mm-text-sm`, `.mm-mt-sm`, `.mm-py-xs`,
  `.mm-clickable`, etc.)
- NEVER use `<div>` as a heading element — use `<h2>` for panel headers,
  `<h3>` for section labels, etc.
- NEVER duplicate styles already covered by existing `mm-*` classes
  (e.g. don't inline `font-size:0.78rem` when `.mm-text-sm` exists)
- NEVER define a CSS class in a template (via `<style>` tags). All CSS
  belongs in `public/css/app.css`.
- NEVER reference CSS classes not defined in `app.css` — run
  `make check-style` to detect orphans.

## Allowed Inline Styles
- Grid/position values from backend data: `grid-template-rows`,
  `grid-row`, `flex:N` where N is data-driven
- Dynamic colors: `background:<%= condition_color %>`
- Conditional cursor: `style="<%= $s->{view} ? 'cursor:pointer' : '' %>"`
- One-off unique values: `margin-right:4px`, `line-height:1.6`,
  `letter-spacing:0.1em`, `border-collapse:collapse`,
  `text-transform:uppercase;letter-spacing:0.05em`

## Composable Class Conventions

### Size utilities (Phase 1)
| Class | Rule |
|-------|------|
| `.mm-text-sm` | `font-size: 0.78rem` |
| `.mm-text-xs` | `font-size: 0.72rem` |
| `.mm-text-2xs` | `font-size: 0.7rem` |
| `.mm-text-3xs` | `font-size: 0.65rem` |
| `.mm-clickable` | `cursor: pointer` |
| `.mm-py-xs` | `padding-top: 0.2rem; padding-bottom: 0.2rem` |
| `.mm-mt-sm` | `margin-top: 0.5rem` |
| `.mm-mb-sm` | `margin-bottom: 0.5rem` |
| `.mm-gap` | `gap: 0.5rem` |
| `.mm-pre` | `white-space: pre-wrap; word-wrap: break-word` |
| `.mm-flex-1` | `flex: 1` |
| `.mm-items-center` | `align-items: center` |
| `.mm-inline-flex` | `display: inline-flex` |

### Text/color utilities
| Class | Rule |
|-------|------|
| `.mm-text-dim` | Dim text color |
| `.mm-text-amber` | Amber text color |
| `.mm-text-bold` | Font-weight 600 |
| `.mm-text-green` / `.mm-text-red` / `.mm-text-cyan` | Color utilities |
| `.mm-center` | `text-align: center` |
| `.text-left` / `.text-center` / `.text-right` | Text alignment |

### Layout/component classes
| Class | Purpose |
|-------|---------|
| `.mm-panel` / `.mm-panel-header` / `.mm-panel-body` | Panel layout structure |
| `.mm-flex` / `.mm-flex-center` / `.mm-flex-between` | Flex layouts |
| `.mm-gap-sm` | 4px gap |
| `.mm-w-full` | Width 100% |
| `.mm-card` / `.mm-card-amber` / `.mm-card-green` | Bordered info cards |
| `.mm-btn` / `.mm-btn-primary` / `.mm-btn-danger` | Buttons |
| `.mm-badge` / `.mm-badge-amber` / `.mm-badge-green` / `.mm-badge-red` | Labels/tags |
| `.mm-ledger` | Data table |
| `.mm-crier` | Indented italic quotation |
| `.mm-empty-state` | Dim centered blurb |
| `.mm-display-label` | Uppercase dim subheading |

## Signs of a Violation
- A template has `style="font-size:...;"` — should be `.mm-text-*`
- A template has `style="cursor:pointer"` — should be `.mm-clickable`
- A template has `style="margin-top:0.5rem"` — should be `.mm-mt-sm`
- A template has `<div class="mm-panel-header">` — should be `<h2>`
- A template uses a CSS class not found in `public/css/app.css`
- A `.html.ep` file contains a `<style>` tag
