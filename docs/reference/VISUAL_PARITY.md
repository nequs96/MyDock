# Visual parity notes

Target reference: Dockset public site/manual and v0.2.6 changelog. No Dockset executable or proprietary assets were used. MyDock uses its own SwiftUI layouts, system symbols, and platform materials.

## Reference surfaces inspected

| Surface | Reference | Observations | Confidence |
|---|---|---|---|
| Stock compact widget | [Public Stock widget preview](https://dockset.app/widget-previews/stock-light.png?v=1) | In the 576 × 184 source image, the light tile uses a soft gray surface, roughly 24 px rounded corners, about 30 px inner padding, a left-aligned ticker/name and large price, green change text, and a compact chart on the right with a subtle dotted fill. The source image is a marketing widget preview, not a direct app screenshot. | Medium |
| Product landing page | [Dockset homepage](https://dockset.app/) | White editorial layout, serif hero headline, restrained blue accent, pastel demo background, floating cards, and translucent Dock imagery. Most UI is marketing imagery rather than a complete app screenshot. | High for visual direction; low for in-app geometry |
| Appearance | [Appearance guide](https://dockset.app/manual/appearance) | Frosted/Liquid Glass surfaces and configurable Dock size and position. | High for available controls |
| Widget/popup behavior | [Custom Dock manual](https://dockset.app/manual/use-custom-docks), [v0.2.6 changelog](https://dockset.app/changelog) | Compact tile plus anchored popout; popout headings/controls are consistent, tall content scrolls, repeated click toggles closed, and Dock scroll pauses while a popout is open. | High for behavior; medium for pixel geometry |

The public site does not provide enough screen coverage for a pixel-perfect comparison of the manager, onboarding, and every widget. Their design is an original interpretation of the reference direction.

## MyDock current geometry

These are implementation values and observations from a safe live preview build:

- Custom Dock: 76 pt high at default size on the bottom edge; 76 pt wide on side edges. The panel now measures rendered 54 pt tiles, preventing the previous 48/54 pt clipping mismatch.
- Bottom widget information cards: 112 × 54 pt, with a live compact value and a two-line label. Compact 54 × 54 pt tiles remain available and are used on side Docks.
- Compact widget labels keep single-word names on one line with modest text scaling, avoiding awkward wraps in narrow side Docks. This last adjustment compiled but has not been inspected in a live preview.
- Item spacing: 8 pt by default, adjustable from 4–18 pt. The surface has 11 pt internal padding.
- Surface: 24 pt rounded rectangle by default, adjustable from 12–32 pt, with 8% profile tint by default, adjustable from 0–30%.
- Manager: 233 pt sidebar in the 1060 × 650 pt default window, original colored widget symbols, and a pale gradient preview field.
- Settings: 860 × 700 pt default window with scrollable rounded sections; onboarding: 760 × 600 pt default window with scrollable steps.

## Comparison status

The DEBUG-only `MYDOCK_VISUAL_PREVIEW=1` mode uses a temporary store and returns before creating the Custom Dock window controller. Live screenshots through the computer-use bridge were inspected for the Custom Dock, Manager, Settings, widget library, and all four onboarding steps. Light and dark appearances showed consistent card treatment, header hierarchy, colors, and readable controls at their default window sizes. Older generated images omitted controls and were discarded; they are not used as parity evidence.

The overflow jump buttons previously covered the first and last tiles. They now occupy separate space beside the scroll viewport. A live overflow check confirmed that the end jump reveals the last running-app tiles without button overlap. The bottom Clock popout was initially placed below its tile; the attachment edge was corrected and a live recheck showed it above the Dock. Left and right Dock previews used compact tiles, and their Clock popouts opened toward the center as intended. Multiple-display placement, the full widget inventory, and accessibility settings remain to be checked on a real desktop. The current evidence does not justify claiming universal pixel parity or that every visual bug is gone.

In the isolated Manager preview, adding a World Clock closed the widget picker and produced a five-item draft. Discard returned the preview to four items with Save disabled; adding Countdown and saving left five items with Save disabled. The profile was also tested with two selected items moved together to the right; Discard restored their original order. Item labels were exposed as accessible buttons. These checks used only the preview's temporary profile store. Shift-click range behavior and persistence across app relaunch remain unchecked.
