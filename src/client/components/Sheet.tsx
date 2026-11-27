import React, { useEffect, useRef } from 'react';

interface SheetProps {
  title: string;
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
}

/** Bottom sheet with a 「完成」 close action, Escape to close, and focus moved into the sheet. */
export const Sheet: React.FC<SheetProps> = ({ title, open, onClose, children }) => {
  const panelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    panelRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('keydown', onKey);
      opener?.focus();
    };
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60" onClick={onClose}>
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-lg max-h-[85dvh] overflow-hidden flex flex-col rounded-t-2xl bg-slate-900 border border-slate-700 pb-safe pl-safe-island pr-safe-island outline-none"
      >
        <div className="shrink-0 flex items-center justify-between gap-2 bg-slate-900 h-11 border-b border-slate-800">
          <h2 className="min-w-0 truncate text-base font-bold text-slate-100">{title}</h2>
          <button
            type="button"
            onClick={onClose}
            className="min-h-[44px] min-w-[44px] px-3 rounded-xl text-base font-bold text-cyan-300"
          >
            完成
          </button>
        </div>
        <div className="py-2 min-h-0 overflow-y-auto">{children}</div>
      </div>
    </div>
  );
};
