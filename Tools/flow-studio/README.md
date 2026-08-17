# LumeSync Flow Studio

A dependency-free workspace for exploring and reviewing the app's iOS UI/UX flow.

## Run it

```sh
python3 -m http.server 8732 --directory Tools/flow-studio
```

Then open <http://localhost:8732/>.

## Workspaces

- **Explore** filters the whole navigation graph by product surface and transition type.
- **Journeys** isolates six critical end-to-end experiences and provides review prompts.
- **Audit** separates graph connectivity, return-only destinations, terminal presentations,
  conditional routes, and high-connectivity hubs.

Select any screen to inspect its source location, incoming and outgoing transitions, conditions,
and presentation style. Review status and notes are saved in the browser's local storage.

## Updating the map

The tool is intentionally a single HTML file:

- `N` contains screen records.
- `E` contains navigation transitions. In-place actions do not belong in this collection.
- `when` marks state-dependent transitions used by context-aware route tracing.
- `JOURNEYS` contains curated UX review sequences and prompts.

Update the source snapshot shown in the footer whenever the graph is retraced.

## Trust boundary

“Graph orphans” means a node in this model cannot be reached from either modeled entry point. It
does **not** prove that every compiled SwiftUI view appears in the model. A compiler-backed source
inventory is still required before declaring code unreachable.
