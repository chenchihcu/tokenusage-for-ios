import React, { useState, useEffect, useLayoutEffect, useRef } from 'react';
import { MasterList } from './MasterList';
import { DetailWorkbench } from './DetailWorkbench';
import { CockpitOverview } from './CockpitOverview';
import { DetailDrawer } from './DetailDrawer';
import { QuotaCardProps } from './QuotaCard';
import { ChevronLeft } from 'lucide-react';
import { DashboardViewMode, HandednessMode } from './ViewModeSelector';
import { haptic } from '../services/haptics';
import { decideColumns, type ColumnMode } from '../network/layout';

interface SplitViewContainerProps {
  quotas: QuotaCardProps[];
  selectedId: string;
  onSelect: (id: string) => void;
  isLoading: boolean;
  viewMode: DashboardViewMode;
  onChangeViewMode: (mode: DashboardViewMode) => void;
  isOnline: boolean;
  linkLabel?: string;
  textScale?: number;
  countdownSeconds: number;
  handedness?: HandednessMode;
  filterAlertOnly?: boolean;
  onToggleFilterAlert?: () => void;
}

export const SplitViewContainer: React.FC<SplitViewContainerProps> = ({
  quotas,
  selectedId,
  onSelect,
  isLoading,
  viewMode,
  isOnline,
  linkLabel,
  textScale = 1,
  countdownSeconds,
  handedness = 'right',
  filterAlertOnly = false,
  onToggleFilterAlert,
}) => {
  const [columns, setColumns] = useState<ColumnMode>(() =>
    typeof window === 'undefined' ? 'single' : decideColumns(window.innerWidth, 1),
  );
  const [isHorizontalDual, setIsHorizontalDual] = useState<boolean>(false);
  const [isVerticalDual, setIsVerticalDual] = useState<boolean>(false);
  const [isFocusMode, setIsFocusMode] = useState<boolean>(false);
  const [showMobileDetail, setShowMobileDetail] = useState<boolean>(false);
  const [drawerOpen, setDrawerOpen] = useState<boolean>(false);
  const openerRef = useRef<HTMLElement | null>(null);
  const wide = columns === 'dual';

  useLayoutEffect(() => {
    const target = document.getElementById('app-content') ?? document.documentElement;
    const apply = (width: number) => setColumns(decideColumns(width, textScale));
    apply(target.clientWidth || window.innerWidth);
    if (typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver((entries) => {
      const width = entries[0]?.contentRect.width ?? target.clientWidth;
      apply(width);
    });
    observer.observe(target);
    return () => observer.disconnect();
  }, [textScale]);

  useEffect(() => {
    const evaluateSegments = () => {
      const isH2 = window.matchMedia?.('(horizontal-viewport-segments: 2)').matches ?? false;
      const isV2 = window.matchMedia?.('(vertical-viewport-segments: 2)').matches ?? false;
      setIsHorizontalDual(isH2);
      setIsVerticalDual(isV2);
    };
    evaluateSegments();
    window.addEventListener('resize', evaluateSegments);
    return () => window.removeEventListener('resize', evaluateSegments);
  }, []);

  useEffect(() => {
    const viewport = window.visualViewport;
    if (!viewport) return;
    const applyInset = () => {
      const overlap = Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop);
      document.documentElement.style.setProperty('--keyboard-inset', `${overlap}px`);
    };
    viewport.addEventListener('resize', applyInset);
    viewport.addEventListener('scroll', applyInset);
    applyInset();
    return () => {
      viewport.removeEventListener('resize', applyInset);
      viewport.removeEventListener('scroll', applyInset);
    };
  }, []);

  useEffect(() => {
    if (typeof window !== 'undefined' && selectedId) {
      const url = new URL(window.location.href);
      url.searchParams.set('provider', selectedId);
      url.searchParams.set('view', viewMode);
      url.searchParams.set('handed', handedness);
      if (filterAlertOnly) {
        url.searchParams.set('filter', 'alert');
      } else {
        url.searchParams.delete('filter');
      }
      if (wide) url.searchParams.set('duo', '1');
      window.history.replaceState({}, '', url.toString());
    }
  }, [selectedId, wide, viewMode, handedness, filterAlertOnly]);

  useEffect(() => {
    if (!showMobileDetail || wide) return;
    document.getElementById('detail-title')?.focus();
  }, [showMobileDetail, wide]);

  const handleItemSelect = (id: string) => {
    haptic.impactLight();
    openerRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    onSelect(id);
    if (!wide && viewMode === 'split') {
      setShowMobileDetail(true);
    }
  };

  const handleOpenDetailDrawer = (id: string) => {
    haptic.impactMedium();
    onSelect(id);
    setDrawerOpen(true);
  };

  const handleBack = () => {
    setShowMobileDetail(false);
    openerRef.current?.focus();
  };

  const selectedItem = quotas.find((q) => q.id === selectedId);
  const listQuotas = filterAlertOnly ? quotas.filter((q) => q.remainingPercent <= 20) : quotas;

  if (isHorizontalDual && wide) {
    return (
      <div className="flex h-full w-full overflow-hidden bg-surface-canvas pl-safe-island pr-safe-island pb-safe">
        <div className="h-full overflow-hidden" style={{ width: 'calc(50% - 8px)' }}>
          <CockpitOverview
            quotas={quotas}
            selectedId={selectedId}
            onSelectPlatform={onSelect}
            onOpenDetail={handleOpenDetailDrawer}
            isOnline={isOnline}
            linkLabel={linkLabel}
            countdownSeconds={countdownSeconds}
            filterAlertOnly={filterAlertOnly}
            onToggleFilterAlert={onToggleFilterAlert}
            handedness={handedness}
            compact={true}
          />
        </div>

        <div
          aria-hidden="true"
          className="w-4 h-full bg-surface-canvas border-x border-border-hairline flex items-center justify-center shrink-0"
        >
          <div className="w-[1px] h-1/3 bg-border-strong rounded-full" />
        </div>

        <div className="h-full overflow-hidden flex-1 min-w-0" style={{ width: 'calc(50% - 8px)' }}>
          <DetailWorkbench
            selectedItem={selectedItem}
            isFocusMode={false}
            onToggleFocus={() => {}}
            handedness={handedness}
            connectionLabel={linkLabel}
          />
        </div>
      </div>
    );
  }

  if (isVerticalDual) {
    return (
      <div className="flex flex-col h-full w-full overflow-hidden bg-surface-canvas pt-safe pb-safe">
        <div className="h-1/2 overflow-hidden border-b border-border-hairline">
          <CockpitOverview
            quotas={quotas}
            selectedId={selectedId}
            onSelectPlatform={onSelect}
            onOpenDetail={handleOpenDetailDrawer}
            isOnline={isOnline}
            linkLabel={linkLabel}
            countdownSeconds={countdownSeconds}
            filterAlertOnly={filterAlertOnly}
            onToggleFilterAlert={onToggleFilterAlert}
            handedness={handedness}
            compact={true}
          />
        </div>
        <div className="h-1/2 min-h-0 overflow-hidden">
          <DetailWorkbench
            selectedItem={selectedItem}
            isFocusMode={false}
            onToggleFocus={() => {}}
            handedness={handedness}
            connectionLabel={linkLabel}
          />
        </div>
      </div>
    );
  }

  if (viewMode === 'cockpit') {
    return (
      <div className="h-full w-full overflow-hidden bg-surface-canvas pl-safe-island pr-safe-island pb-safe">
        <CockpitOverview
          quotas={quotas}
          selectedId={selectedId}
          onSelectPlatform={onSelect}
          onOpenDetail={handleOpenDetailDrawer}
          isOnline={isOnline}
          linkLabel={linkLabel}
          countdownSeconds={countdownSeconds}
          filterAlertOnly={filterAlertOnly}
          onToggleFilterAlert={onToggleFilterAlert}
          handedness={handedness}
        />
        <DetailDrawer
          item={selectedItem}
          open={drawerOpen}
          onClose={() => setDrawerOpen(false)}
          connectionLabel={linkLabel}
        />
      </div>
    );
  }

  if (wide) {
    return (
      <div className="flex h-full w-full overflow-hidden bg-surface-canvas pl-safe-island pr-safe-island pb-safe">
        <aside
          aria-label="AI 平台清單"
          className={`h-full transition-all duration-200 overflow-hidden ${
            isFocusMode
              ? 'w-0 opacity-0 pointer-events-none'
              : 'w-[38%] min-w-[260px] max-w-[400px] opacity-100'
          }`}
        >
          <MasterList
            quotas={listQuotas}
            selectedId={selectedId}
            onSelect={handleItemSelect}
            isLoading={isLoading}
          />
        </aside>

        <main aria-label="服務詳情" className="flex-1 h-full min-w-0 bg-surface-canvas">
          <DetailWorkbench
            selectedItem={selectedItem}
            isFocusMode={isFocusMode}
            onToggleFocus={() => setIsFocusMode(!isFocusMode)}
            handedness={handedness}
            connectionLabel={linkLabel}
          />
        </main>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full w-full overflow-hidden bg-surface-canvas pt-safe pb-safe">
      {showMobileDetail ? (
        <div className="flex flex-col h-full">
          <div className="p-3 border-b border-border-hairline flex items-center bg-surface-card">
            <button
              type="button"
              onClick={handleBack}
              className="flex items-center gap-1 text-body font-bold text-accent-primary active:opacity-70 transition-opacity min-h-[44px]"
            >
              <ChevronLeft className="w-5 h-5" aria-hidden="true" />
              返回清單
            </button>
          </div>
          <div className="flex-1 min-h-0 overflow-hidden">
            <DetailWorkbench
              selectedItem={selectedItem}
              isFocusMode={false}
              onToggleFocus={() => {}}
              handedness={handedness}
              connectionLabel={linkLabel}
            />
          </div>
        </div>
      ) : (
        <MasterList
          quotas={listQuotas}
          selectedId={selectedId}
          onSelect={handleItemSelect}
          isLoading={isLoading}
        />
      )}
    </div>
  );
};
