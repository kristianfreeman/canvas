# Positioning panels

**Placement** is the set of options that decides where a Canvas panel opens, how big it is, which edge stays put when its content changes height, and how the window behaves. It lets you put a HUD in a corner, a dialog at the cursor, or a dashboard across half a display without measuring screens yourself. This page covers every placement option, the coordinate conventions, growth anchors, remembered frames, stacks, `canvas move`, and five recipes. Each recipe's frame is checked by a test in `Tests/CanvasTests/PositioningRecipeTests.swift`.

The worked numbers on this page use a 14" MacBook Pro: a 1512 × 982 pt screen whose visible frame (the screen minus the menu bar and the Dock) is 1512 × 944 pt at the origin. Panels default to 720 pt wide, and the examples assume a page 400 pt tall unless they say otherwise.

## Coordinates

Frames that Canvas reports (`canvas list`, the `moved` event) are in AppKit global coordinates. The origin is the bottom-left corner of the main display, y grows upward, and units are points. A display to the left of the main one has negative x, and a display above it has y past the main display's height.

`--at` uses the other convention, because it's the one people think in. It measures from the top-left corner of the chosen screen's visible frame, with y growing downward. A negative value measures from the far edge: a negative x sets the panel's right edge that far from the right, and a negative y sets its bottom edge that far from the bottom. `-0` therefore means flush right or flush bottom.

Percentages are of the visible frame. Horizontal values (`--at` x, `--width`) take the visible width, and vertical values (`--at` y, `--height`, `--min-height`, `--max-height`) take the visible height. Canvas rounds percentages down to whole points, but a size never rounds below 1 pt. When centering lands on half a point, it rounds down too.

Every frame Canvas computes lies fully inside the visible frame. A panel larger than the visible frame shrinks to fit, and one that would cross an edge slides back inside.

## Placement options

`show`, `toggle` and `move` accept the same placement options. On the wire each one is a field of the request (see `docs/protocol.md`). The CLI sends only the options you give, so the server can tell an explicit `--position center` from the default.

| Option | Values | Default |
|---|---|---|
| `--position P` | `center`, `top`, `bottom`, `left`, `right`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `mouse` | `center` |
| `--at X,Y` | Points or `N%`, negative from the right or bottom. Overrides `--position`. | none |
| `--screen S` | `mouse`, `main`, `focused`, a 1-based index, or part of a display name | `mouse` |
| `--margin N` | Points from the screen edges for presets, 0 or more | 24, and 64 from the top for `top` |
| `--width N\|N%` | Positive points or percent | 720 |
| `--height N\|N%` | A fixed height | follows the content |
| `--min-height N\|N%` | Floor for the height | 80 |
| `--max-height N\|N%` | Cap for the content-driven height | 85% |
| `--resizable` / `--no-resizable` | Whether the user can drag the edges | resizable |
| `--level L` | `normal`, `floating`, `top` | `floating` |
| `--spaces S` | `all`, `current` | `all` |
| `--pin` | Floating level or higher, all Spaces, Esc doesn't close | off |
| `--click-through` | The panel ignores the mouse | off |
| `--opacity F` | 0.0 to 1.0 | 1 |
| `--stack GROUP` | A stack group name | none |
| `--forget` | Clear this id's remembered frame | off |

An invalid value fails the request with a message that names the option and what it expected, for example `invalid opacity 2: expected a number from 0 to 1`.

### Presets and margins

Each preset aligns the panel to a point on the visible frame. `center` centers it on both axes and ignores `--margin`. `left` and `right` keep the margin from that side and center vertically. `top` and `bottom` center horizontally, with `top` 64 pt below the top edge and `bottom` 24 pt above the bottom edge. The four corners keep the margin from both of their edges. Giving `--margin` replaces every one of those distances, so `--position top --margin 0` sits flush against the menu bar.

On the laptop, a 720 × 400 panel lands here:

| Position | Frame (x, y, width, height) |
|---|---|
| `center` | 396, 272, 720, 400 |
| `top` | 396, 480, 720, 400 |
| `bottom` | 396, 24, 720, 400 |
| `left` | 24, 272, 720, 400 |
| `right` | 768, 272, 720, 400 |
| `top-left` | 24, 520, 720, 400 |
| `top-right` | 768, 520, 720, 400 |
| `bottom-left` | 24, 24, 720, 400 |
| `bottom-right` | 768, 24, 720, 400 |

`--position mouse` puts the panel's top-left corner 12 pt right of and 12 pt below the cursor. When that would run off the right edge, the panel flips to the cursor's left. When it would run off the bottom, it flips above the cursor. It's then nudged inside the visible frame like any other frame.

`--at` ignores both `--position` and `--margin`. `--at 100,50` puts the top-left corner 100 pt from the left and 50 pt from the top, which is the frame (100, 494, 720, 400) on the laptop. `--at -24,-24` puts the bottom-right corner 24 pt from both edges, which matches `bottom-right`.

### Screens

`--screen` picks the display, and the placement then uses that display's visible frame.

- **`mouse`:** the display under the cursor, or the nearest one when the cursor is between displays.
- **`main`:** the display with the menu bar.
- **`focused`:** the display that has most of the frontmost app's focused window.
- **`N`:** the Nth display in the system's order, counting from 1.
- **`NAME`:** the first display whose name contains NAME, ignoring case, such as `dell` for "DELL U2723QE".

A selector that matches nothing, like `--screen 3` with two displays or `focused` with no window, falls back to the display under the cursor.

### Sizes

The width is `--width`, at least 240 pt and at most the visible width. A width the user dragged to replaces it until a later request gives `--width` again.

With `--height`, the panel is that tall, raised to `--min-height` and capped at the visible height. Without it, the height follows the page: the page's height rounded up, at least `--min-height`, and at most `--max-height` and the visible height. Past that the page scrolls. Until the page reports its height, Canvas uses 200 pt. When `--min-height` is larger than `--max-height`, the maximum wins.

### Window behavior

`--level normal` puts the panel among ordinary windows, `floating` keeps it above them, and `top` raises it above full-screen apps and the menu bar. `--spaces current` keeps the panel on the Space it opened on.

`--pin` is for panels that should stay up. It raises a `normal` level to `floating`, forces `--spaces all`, and makes Esc leave the panel open. Close a pinned panel with its × or `canvas hide`. `--click-through` passes every click to the window underneath. A click-through panel can't be dragged or closed with the mouse, so close it with `canvas hide --id ID`.

## Growth anchors

When a panel's height changes, its **growth anchor** decides which edge stays put. Without an anchor, a top-right status panel whose page grows would slide down off its corner.

- `top`, `top-left` and `top-right` keep the top edge and grow downward.
- `bottom`, `bottom-left` and `bottom-right` keep the bottom edge and grow upward.
- `center`, `left` and `right` keep their vertical center and grow both ways.
- `--at` keeps the top edge when y is zero or positive, and the bottom edge when y is negative.
- `mouse` keeps the edge nearest the cursor after any flip. A panel that opened below the cursor grows downward. One that flipped above it grows upward.

Horizontally the same rule keeps the left edge, the right edge or the center, which matters when a later request changes the width.

A panel that grows past the visible frame slides back inside instead of crossing the edge. When its content shrinks again, it returns to its anchored position. After the user drags a panel, its anchor becomes the visible frame's nearer edge on each axis.

## Remembered frames

When you drag or resize a panel, Canvas saves its frame under its id, so the panel comes back where you put it. The frames live in `$CANVAS_HOME/frames.json`, by default `~/Library/Application Support/Canvas/frames.json`.

Frames are saved per display arrangement. The arrangement is the set of display frames, regardless of the order macOS lists them in. Showing or hiding the Dock doesn't change it, but plugging in, unplugging or rearranging a display does. Each arrangement keeps its own frames, so a panel can sit on the external display while docked and in a laptop corner while away.

A saved frame records the origin, the size and the anchor. The anchor is the visible frame's nearer edge on each axis, with ties going to the top and the left. A panel you dragged into the bottom-right corner keeps its bottom and right edges when its content grows.

A later `show` or `toggle` for the same id restores the frame when the request gives none of `--position`, `--at` or `--stack`.

- The restored width is the saved one, unless the request gives `--width`. An explicit width wins and is laid out from the saved anchor, so a right-anchored panel keeps its right edge.
- The height still follows the page, growing from the saved anchored edge.
- If the request gives `--screen` and it names a different display than the saved frame's, the placement wins.
- A frame on a display that's no longer connected is ignored.
- A missing or unreadable `frames.json` counts as empty and is rewritten on the next save. Writes are atomic.

`--forget` clears the id's frames in every arrangement and places the panel from its options. `canvas move` doesn't save a frame. Only the user's drags and resizes do.

## Stacks

A **stack** is a group of panels that share a corner and line up instead of covering each other, like notifications. Give each panel the same `--stack GROUP` and its own `--id`.

The oldest panel in the group sits where its placement puts it. Each later panel keeps its own x and sits 12 pt past the previous one, away from the anchored edge: below it for top and center anchors, above it for bottom anchors. The group uses the oldest panel's anchor and display. When a panel in the group closes or changes height, the rest reflow to close the gap.

When the next slot would run off the visible frame, the panel stops at that edge and overlaps the panel before it. No stacked panel is ever off screen. Stacked panels don't restore remembered frames, because the stack decides their place.

Dragging a stacked panel takes it out of its group: it stays where you drop it, and the rest of the group reflows to close the gap. Resizing one keeps it in the group. A later `show` or `toggle` with `--stack` puts it back.

## Moving an open panel

`canvas move --id ID [placement options]` changes the placement of an open panel. The options are merged onto the panel's current placement, so anything you don't give keeps its current value. The server answers with the new frame, and `move` never starts the server.

- `--position`, `--at`, `--screen`, `--margin` and `--stack` place the panel again from scratch. `--position` without `--at` drops an earlier `--at`, which would otherwise still override it.
- `--width`, `--height`, `--min-height` and `--max-height` resize the panel around its growth anchor. `--width` also drops a width the user dragged to.
- The window options (`--level`, `--spaces`, `--pin`, `--click-through`, `--opacity`, `--resizable`) apply in place without moving the panel.

Send the panel to the bottom-right corner:

```bash
canvas move --id cpu --position bottom-right
```

Make the cheat sheet half the display wide, keeping its center:

```bash
canvas move --id cheatsheet --width 50%
```

A `show` for an id that's already open merges its placement the same way, so replacing content leaves the panel where it is unless the new request positions it.

## Recipes

Each recipe gives the command and the frame it produces on the test displays. The tests use the laptop as display 1 (the main display), a 2560 × 1440 display to its left at x = −2560 as display 2, and a portrait display above.

### CPU HUD in the top-right of the main display

**Use when:** you want a small always-visible readout that never takes a click.

Save this as `cpu.tsx`:

```tsx
import { Card, Progress, Stat, useChannel } from 'canvas'

export default function Cpu() {
  const cpu = useChannel<{ total: number }>('canvas.sys.cpu')
  const percent = Math.round((cpu?.total ?? 0) * 100)
  return (
    <Card>
      <Stat label="CPU" value={`${percent}%`} />
      <Progress value={percent} />
    </Card>
  )
}
```

**To use:**

```bash
canvas show cpu.tsx --id cpu --screen main --position top-right --width 320 --pin --click-through --opacity 0.85
```

The panel goes on the menu-bar display wherever the cursor is. Its right edge is 24 pt from the right and its top edge 24 pt below the menu bar, so a 180 pt page is the frame (1168, 740, 320, 180). It grows downward, stays on every Space, and ignores Esc and clicks. Close it with `canvas hide --id cpu`.

### Hotkey-toggled cheat sheet

**Use when:** one key should open and close a reference sheet in the middle of the screen.

**To use:** bind this command to the hotkey (Hyper+I, say):

```bash
canvas toggle examples/keys.tsx --id cheatsheet --position center --width 880 --data - < examples/keys.json
```

The first press opens an 880 pt sheet centered on the display under the cursor. A 600 pt page is the frame (316, 172, 880, 600) on the laptop. The next press hides it. Because the command gives `--position`, the sheet always reopens centered even if you dragged it. Leave out `--position center` to have it reopen where you last put it.

### Approval dialog at the mouse

**Use when:** a script needs a yes or no and you want the question where you're looking.

**To use:**

```bash
canvas show examples/approve.tsx --position mouse --width 420 --wait
```

With the cursor at (1000, 600) in AppKit coordinates, a 300 pt dialog opens 12 pt right of and below it, at the frame (1012, 288, 420, 300). It's anchored to its top-left corner, so it grows downward. The command blocks until you choose, prints the result as JSON, and exits 0. Esc or × exits 2.

### Dashboard filling the right half of a second display

**Use when:** a dashboard should take over half of an external monitor.

**To use:**

```bash
canvas show examples/dashboard.tsx --screen 2 --position right --margin 0 --width 50% --height 100%
```

Display 2's visible frame is (−2560, 0, 2560, 1415), so the panel is the frame (−1280, 0, 1280, 1415): its right half, full height, flush with the edges. `--screen dell` picks the same display by name. `--at -0,0` with the same sizes gives the same frame.

### Stacked notifications

**Use when:** several short messages arrive and each should stay visible until dismissed.

**To use:** give each message its own id and the same group:

```bash
echo '**Build finished**' | canvas show - --id note-1 --stack notes --position top-right --width 360
echo '**Tests passed** in 41 s' | canvas show - --id note-2 --stack notes --position top-right --width 360
echo '**Deployed** to staging' | canvas show - --id note-3 --stack notes --position top-right --width 360
```

With pages 100, 150 and 80 pt tall, the notes are the frames (1128, 820, 360, 100), (1128, 658, 360, 150) and (1128, 566, 360, 80). Each one's top edge is 12 pt below the one before. After `canvas hide --id note-2`, the third note moves up to (1128, 728, 360, 80).
