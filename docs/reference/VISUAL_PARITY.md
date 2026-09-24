# Visual parity notes

Target reference: Dockset public site/manual and v0.2.6 changelog. No Dockset executable or proprietary assets were used.

## Reference surfaces inspected

| Surface | Reference | Observations | Confidence |
|---|---|---|---|
| Stock compact widget | [Public Stock widget preview](https://dockset.app/widget-previews/stock-light.png?v=1) | In the 576 × 184 source image, the light tile uses a soft gray surface, roughly 24 px rounded corners, about 30 px inner padding, a left-aligned ticker/name and large price, green change text, and a compact chart on the right with a subtle dotted fill. The source image is a marketing widget preview, not a direct app screenshot. | Medium |
| Product landing page | [Dockset homepage](https://dockset.app/) | White editorial layout, centered hero headline and restrained navigation; most Dock UI is represented as embedded product imagery rather than a complete app screenshot. | Low for in-app geometry |
| Widget/popup behavior | [Custom Dock manual](https://dockset.app/manual/use-custom-docks), [v0.2.6 changelog](https://dockset.app/changelog) | Compact tile plus anchored popout; popout headings/controls are consistent, tall content scrolls, repeated click toggles closed, and Dock scroll pauses while a popout is open. | High for behavior; medium for pixel geometry |

The manual's getting-started and custom-Dock image fetches timed out in the reference browser. The images that loaded directly from the site were a background mesh and the Stock card, so pixel comparisons against the manager or full Dock are not yet possible.

## MyDock current geometry

These are implementation values, not verified parity measurements:

- Custom Dock: 86 px high on the bottom edge; 88 px wide on side edges.
- App/widget icon frame: 48 px, with an 8 px inter-item gap and 11 px internal padding.
- Surface: 24 px rounded rectangle using macOS ultra-thin material and a 1 px highlight border.
- Manager cards: 58 px app icon and 14 px card radius.

## Comparison status

No screenshot of the MyDock app has been captured. The computer-use accessibility bridge timed out binding to the locally built MyDock app, so spacing, typography, icon sizing, popup placement, animation, and dark-mode parity remain unchecked. Update this document after a reproducible app screenshot is available.
