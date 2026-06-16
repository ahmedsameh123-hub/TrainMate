# TrainMate backend documentation

## Primary format (recommended)

Open **`BACKEND_DOCUMENTATION.html`** in a desktop browser (Chrome, Edge, or Firefox).

- **English** technical write-up with tables and styling  
- **PNG diagrams** under `images/` (visible without JavaScript)  
- **Optional Mermaid** live SVG diagrams when scripts are allowed  
- Inline **SVG** stack diagram in the header  
- **Print → Save as PDF** works for a single shareable file  

## Diagram sources

| PNG | Mermaid source |
|-----|----------------|
| `images/use-case.png` | `diagrams/01-use-case.mmd` |
| `images/class-orm.png` | `diagrams/02-class-orm.mmd` |
| `images/sequence-protected.png` | `diagrams/03-sequence-protected.mmd` |
| `images/sequence-auth.png` | `diagrams/04-sequence-auth.mmd` |
| `images/sequence-workout-chat.png` | `diagrams/05-sequence-workout-chat.mmd` |

Regenerate PNGs (readable text + arrows: **scale 2.5**, wide canvas). Requires [Node.js](https://nodejs.org/) (first `npx` run may download Chromium):

```powershell
cd trainmate_backend\docs
npx -y @mermaid-js/mermaid-cli@10 -i diagrams/01-use-case.mmd -o images/use-case.png -b "#ffffff" -s 2.5 -w 2400
npx -y @mermaid-js/mermaid-cli@10 -i diagrams/02-class-orm.mmd -o images/class-orm.png -b "#ffffff" -s 2.5 -w 2800
npx -y @mermaid-js/mermaid-cli@10 -i diagrams/03-sequence-protected.mmd -o images/sequence-protected.png -b "#ffffff" -s 2.5 -w 2600
npx -y @mermaid-js/mermaid-cli@10 -i diagrams/04-sequence-auth.mmd -o images/sequence-auth.png -b "#ffffff" -s 2.5 -w 2800
npx -y @mermaid-js/mermaid-cli@10 -i diagrams/05-sequence-workout-chat.mmd -o images/sequence-workout-chat.png -b "#ffffff" -s 2.5 -w 2800
```

Diagrams use **dark navy** (`#0f172a`) for text and connector lines, **blue** (`#1d4ed8`) for sequence message arrows, and **large font sizes** in each `%%{init:...}%%` block.

## Arabic Markdown (legacy)

The older Arabic-only Markdown file lives at `../BACKEND_DOCUMENTATION_AR.md` and may lag behind the HTML doc.
