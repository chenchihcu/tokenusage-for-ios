/**
 * Minimum readable widths for the list and the detail pane.
 * VERIFY on an iPhone Duo install; these are layout suggestions, not hardware specs.
 */
export const LIST_MIN_PX = 280;
export const DETAIL_MIN_PX = 320;
export const COLUMN_GUTTER_PX = 16;
export const SINGLE_COLUMN_TEXT_SCALE = 1.6;

export type ColumnMode = 'single' | 'dual';

export function decideColumns(containerWidth: number, textScale: number): ColumnMode {
  if (!Number.isFinite(containerWidth) || containerWidth <= 0) return 'single';
  const scale = Number.isFinite(textScale) && textScale > 0 ? textScale : 1;
  if (scale >= SINGLE_COLUMN_TEXT_SCALE) return 'single';
  const needed = (LIST_MIN_PX + DETAIL_MIN_PX) * Math.max(scale, 1) + COLUMN_GUTTER_PX;
  return containerWidth >= needed ? 'dual' : 'single';
}
