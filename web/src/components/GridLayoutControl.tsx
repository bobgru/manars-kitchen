import { GRID_LAYOUTS, type GridLayout } from "../lib/grid";

interface Props {
  value: GridLayout;
  onChange: (layout: GridLayout) => void;
}

/**
 * The pivot: which of the named grid layouts to draw. The choice is the
 * caller's state -- both pages keep it in the URL as `?layout=` so a view can
 * be linked to, the way the calendar keeps its range -- and this only renders
 * the segments. The pressed one is marked by weight, border and `aria-pressed`,
 * not by hue alone.
 */
export default function GridLayoutControl({ value, onChange }: Props) {
  return (
    <div className="layout-bar" role="group" aria-label="Grid layout">
      {GRID_LAYOUTS.map((l) => (
        <button
          key={l.id}
          type="button"
          className={l.id === value ? "layout-seg layout-seg-on" : "layout-seg"}
          aria-pressed={l.id === value}
          onClick={() => onChange(l.id)}
        >
          {l.label}
        </button>
      ))}
    </div>
  );
}
