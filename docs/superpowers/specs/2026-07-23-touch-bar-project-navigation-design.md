# Touch Bar Project Navigation Design

## Goal

Make project status quieter and provide a dedicated expanded project browser when many Codex projects are present.

## Compact Project Mode

- Keep the horizontally scrollable project scrubber in the normal Touch Bar layout.
- Reduce its width by exactly the width and spacing required for one native navigation button.
- Add a trailing `>` button using the same `texturedRounded` AppKit button treatment as the existing Touch Bar controls.
- Keep weekly limit, Effort, and Speed controls unchanged.

## Expanded Project Mode

- Tapping `>` replaces the normal layout with a full-width project scrubber and a trailing `<` button.
- Hide weekly limit, Effort, and Speed while expanded so the available width is dedicated to projects.
- Preserve project ordering, scrolling, unread priority, current-project state, and project tapping behavior.
- Tapping `<` returns to compact project mode.

## Project Cell Styling

- Render folder icons, project names, and task counts in white.
- Render only the unread trailing dot in system purple.
- Remove the yellow selected color and the leading `▶` marker.
- Indicate the selected project with a persistent rounded dark background matching the visual weight of native Touch Bar buttons.
- Keep placeholder cells visually muted and without selected or unread decoration.
- Preserve accessibility labels for current-project and unread-result state.

## Architecture

- Extend `TouchBarLayoutMode` with a dedicated expanded-project state.
- Keep the expanded/collapsed transition in `TouchBarLayoutState`.
- Add separate expand and collapse Touch Bar item identifiers and native `NSButton` views in `TouchBarController`.
- Let `ProjectScrubberItemView` own selected-cell background styling.
- Extend `TouchBarImageRenderer` to draw an optional independently colored trailing indicator so the unread dot can be purple while the rest remains white.

## Testing

- Layout-state tests cover compact → expanded → compact transitions.
- Title-rendering tests confirm selected projects no longer include `▶`.
- Renderer tests confirm the unread indicator is modeled separately from the white title.
- Cell-style tests cover selected background visibility and reuse reset behavior.
- Existing project ordering, tapping, weekly-limit, Effort, and Speed tests must remain green.

## Acceptance Criteria

- Compact mode gains one native-looking trailing `>` button without crowding existing right-side controls.
- Expanded mode shows the widest practical project scrubber and a trailing `<` button.
- Selected projects use only a dark rounded background.
- Unread projects use only a purple dot; their folder, name, and count remain white.
- Project state changes remain live without restarting the helper.
