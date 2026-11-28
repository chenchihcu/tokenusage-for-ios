import React, { useEffect, useId, useRef } from 'react';

interface SheetProps {
  title: string;
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
}

/** Native modal <dialog> sheet with 「完成」 close action, light dismiss, and scroll containment. */
export const Sheet: React.FC<SheetProps> = ({ title, open, onClose, children }) => {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const titleId = useId();

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      dialog.showModal();
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open]);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    const onCloseEvent = () => {
      dialog.returnValue = '';
      onClose();
    };
    dialog.addEventListener('close', onCloseEvent);

    if ('closedBy' in HTMLDialogElement.prototype) {
      return () => dialog.removeEventListener('close', onCloseEvent);
    }

    const outside = (e: PointerEvent) => {
      const r = dialog.getBoundingClientRect();
      return e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom;
    };
    let pressedOutside = false;
    const onDown = (e: PointerEvent) => {
      pressedOutside = outside(e);
    };
    const onUp = (e: PointerEvent) => {
      if (pressedOutside && outside(e)) dialog.close();
      pressedOutside = false;
    };
    dialog.addEventListener('pointerdown', onDown);
    dialog.addEventListener('pointerup', onUp);
    return () => {
      dialog.removeEventListener('close', onCloseEvent);
      dialog.removeEventListener('pointerdown', onDown);
      dialog.removeEventListener('pointerup', onUp);
    };
  }, [onClose]);

  return (
    <dialog
      ref={dialogRef}
      closedby="any"
      aria-labelledby={titleId}
      className="m-0 mt-auto mx-auto w-full max-w-lg max-h-[85dvh] rounded-t-2xl bg-surface-card text-ink-primary border border-border-hairline shadow-hig-dock p-0 pb-safe pl-safe-island pr-safe-island open:flex flex-col overflow-hidden"
    >
      <div className="shrink-0 flex items-center justify-between gap-2 h-12 border-b border-border-hairline bg-surface-card">
        <h1 id={titleId} className="min-w-0 truncate text-heading-section font-bold text-ink-primary">
          {title}
        </h1>
        <button
          type="button"
          onClick={onClose}
          className="min-h-[44px] min-w-[44px] px-3 rounded-xl text-body font-bold text-accent-primary hover:bg-surface-muted focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary"
        >
          完成
        </button>
      </div>
      <div className="py-3 min-h-0 overflow-y-auto">{children}</div>
    </dialog>
  );
};
