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
- Compact widget labels keep single-word names on one line with modest text scaling, avoiding awkward wraps in narrow side Docks. The live bottom-Dock preview shows the Countdown title on one line without an orphan character.
- Item spacing: 8 pt by default, adjustable from 4–18 pt. The surface has 11 pt internal padding.
- Surface: 24 pt rounded rectangle by default, adjustable from 12–32 pt, with 8% profile tint by default, adjustable from 0–30%.
- Manager: 233 pt sidebar in the 1060 × 650 pt default window, original colored widget symbols, and a pale gradient preview field.
- Settings: 860 × 700 pt default window with scrollable rounded sections; onboarding: 760 × 600 pt default window with scrollable steps.

## Comparison status

The DEBUG-only visual preview uses a per-process temporary store and returns before creating the Custom Dock window controller. It activates either with `MYDOCK_VISUAL_PREVIEW=1` or the dedicated preview bundle identifier, so launching the preview app directly remains isolated. Live screenshots through the computer-use bridge were inspected for the Custom Dock, Manager, Settings, widget library, and all four onboarding steps. Light and dark appearances showed consistent card treatment, header hierarchy, colors, and readable controls at their default window sizes. Older generated images omitted controls and were discarded; they are not used as parity evidence.

The overflow jump buttons previously covered the first and last tiles. They now occupy separate space beside the scroll viewport. A live overflow check confirmed that the end jump reveals the last running-app tiles without button overlap. The bottom Clock popout was initially placed below its tile; the attachment edge was corrected and a live recheck showed it above the Dock. Left and right Dock previews used compact tiles, and their Clock popouts opened toward the center as intended. The Manager's large editable profile name was also clipped by the Preview toolbar; reserving the text field's full height moved the divider below the name, confirmed in the default-size live preview. Multiple-display placement, the full widget inventory, and accessibility settings remain to be checked on a real desktop. The current evidence does not justify claiming universal pixel parity or that every visual bug is gone.

The Weather popout's manual city search returned London, England, United Kingdom; selecting it loaded and displayed a current Open-Meteo forecast and updated the compact tile. Celsius/Fahrenheit conversion and Current, Conditions, and Hourly layouts updated in place. This used a generic city in the isolated profile and did not invoke location services.

In the isolated Manager preview, adding a World Clock closed the widget picker and produced a five-item draft. Discard returned the preview to four items with Save disabled; adding Countdown and saving left five items with Save disabled. The live compact preview then showed Countdown at the overflow end with its title on one line. Its anchored popout displayed the timer controls; Start changed to Pause, Pause stopped the countdown, Reset restored 5:00, and Command-W closed the popout while leaving the Dock preview open. The profile was also tested with two selected items moved together to the right; Discard restored their original order. Item labels were exposed as accessible buttons. These checks used only the preview's temporary profile store. Shift-click range behavior and persistence across app relaunch remain unchecked.

A separate isolated preview seeded a Countdown with an absolute target about 25 hours ahead. The compact tile displayed `1d`; the expanded value showed days, hours, minutes, and seconds. The initial small-window capture cropped the native popover at the preview window boundary, so the date-mode preview canvas was enlarged to 960 × 560 pt. The final capture showed the entire 300 pt popout, including the value, segmented mode picker, date field, Update/Clear actions, target summary, and wrapped explanatory text. Switching to Duration exposed Start, Reset, and the duration stepper in the same popout. This verified control layout in the disposable preview; it did not schedule a notification or validate placement across physical displays.

The refreshed isolated preview displayed the 24-hour local window-preview cache explanation in Settings without clipping. Enabling Show minimized windows made its dependent Cache window previews control available; no Screen Recording permission was requested. A right-click on the Dock surface opened Switch Profile → Custom Dock. After creating and naming a disposable second profile in Manager, the menu marked that profile active. Selecting Everyday from the menu moved the checkmark back to Everyday on reopening. The preview surface itself is tied to its seed profile, so this check verifies menu state and selection, not a live Dock panel replacement.

The General tab's Back Up and Restore buttons were exercised in the isolated preview. The saved JSON contained one Everyday profile; Restore appended a second Everyday row with the same Clock, Weather, Focus Timer, and Sticky Note items. Settings still showed the original Everyday profile selected. The temporary archive was removed after the check. This verifies the user-facing save/open flow on disposable data; it does not prove recovery of a real user's profile store or future schema migration.

AI Limits was added through the widget library in the isolated preview. Its default three visible providers generate more setup guidance than fits a short window. The popout now has a bounded 480 pt vertical scroll area; accessibility exposed the scrollbar and scrolling moved it from the top to the bottom, making the final guidance reachable. The 620 × 420 pt preview capture crops the native popover outside the preview window, so it does not establish full popover placement on the physical display.
