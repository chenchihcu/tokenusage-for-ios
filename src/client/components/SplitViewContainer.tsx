import React, { useState, useEffect, useLayoutEffect, useRef } from 'react';
import { MasterList } from './MasterList';
import { DetailWorkbench } from './DetailWorkbench';
import { CockpitOverview } from './CockpitOverview';
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
  isVoiceActive: boolean;
  liveTranscript: string;
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
  isVoiceActive,
  liveTranscript,
  viewMode,
  onChangeViewMode,
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
  const openerRef = useRef<HTMLElement | null>(null);
  const wide = columns === 'dual';

  // 欄數只看內容寬度與文字縮放。折疊媒體查詢有支援時才啟用，窄空間仍退回單欄。
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

  // URL 深度連結同步 (State Restoration: 平台選取與視圖模式)
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

  const handleOpenDetail = (id: string) => {
    haptic.impactMedium();
    openerRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    onSelect(id);
    onChangeViewMode('split');
    if (!wide) {
      setShowMobileDetail(true);
    }
  };

  const handleBack = () => {
    setShowMobileDetail(false);
    openerRef.current?.focus();
  };

  const selectedItem = quotas.find((q) => q.id === selectedId);

  // =========================================================================
  // 特殊形態 A：W3C Viewport Segments 雙屏水平展開 (horizontal-viewport-segments: 2)
  // 左螢幕全景 Cockpit : 右螢幕深入 Detail，中央轉軸安全避讓縫隙 (Hinge Seam Guard)
  // =========================================================================
  if (isHorizontalDual && wide) {
    return (
      <div className="flex h-full w-full overflow-hidden bg-slate-950 pl-safe-island pr-safe-island pb-safe">
        {/* 左屏：CockpitOverview (Segment 0 0) */}
        <div
          className="h-full overflow-hidden"
          style={{ width: 'calc(50% - 8px)' }}
        >
          <CockpitOverview
            quotas={quotas}
            selectedId={selectedId}
            onSelectPlatform={onSelect}
            onOpenDetail={handleOpenDetail}
            isOnline={isOnline}
            linkLabel={linkLabel}
            countdownSeconds={countdownSeconds}
            filterAlertOnly={filterAlertOnly}
            onToggleFilterAlert={onToggleFilterAlert}
            handedness={handedness}
            compact={true}
          />
        </div>

        {/* 硬體轉軸鉸鏈中隔避讓槽 (Hinge Spine Seam - 零數據落於物理折縫) */}
        <div
          aria-hidden="true"
          className="w-4 h-full bg-slate-950 border-x border-slate-900 flex items-center justify-center shrink-0"
        >
          <div className="w-[1px] h-1/3 bg-slate-850 rounded-full" />
        </div>

        {/* 右屏：DetailWorkbench (Segment 1 0) */}
        <div
          className="h-full overflow-hidden flex-1 min-w-0"
          style={{ width: 'calc(50% - 8px)' }}
        >
          <DetailWorkbench
            selectedItem={selectedItem}
            isFocusMode={false}
            onToggleFocus={() => {}}
            isVoiceActive={isVoiceActive}
            liveTranscript={liveTranscript}
            handedness={handedness}
            connectionLabel={linkLabel}
          />
        </div>
      </div>
    );
  }

  // =========================================================================
  // 特殊形態 B：W3C Viewport Segments 垂直折疊筆電態 (vertical-viewport-segments: 2)
  // 上半屏只讀圖表監控中樞 : 下半屏觸控控制台
  // =========================================================================
  if (isVerticalDual) {
    return (
      <div className="flex flex-col h-full w-full overflow-hidden bg-slate-950 pt-safe pb-safe">
        <div className="h-1/2 overflow-hidden border-b border-slate-800">
          <CockpitOverview
            quotas={quotas}
            selectedId={selectedId}
            onSelectPlatform={onSelect}
            onOpenDetail={handleOpenDetail}
            isOnline={isOnline}
            linkLabel={linkLabel}
            countdownSeconds={countdownSeconds}
            filterAlertOnly={filterAlertOnly}
            onToggleFilterAlert={onToggleFilterAlert}
            handedness={handedness}
            compact={true}
          />
        </div>
        <div className="h-1/2 overflow-y-auto">
          <DetailWorkbench
            selectedItem={selectedItem}
            isFocusMode={false}
            onToggleFocus={() => {}}
            isVoiceActive={isVoiceActive}
            liveTranscript={liveTranscript}
            handedness={handedness}
            connectionLabel={linkLabel}
          />
        </div>
      </div>
    );
  }

  // ==========================================
  // 標準模式 A：一頁式全景矩陣駕駛艙 (Cockpit - Includes All)
  // ==========================================
  if (viewMode === 'cockpit') {
    return (
      <div className="h-full w-full overflow-hidden bg-slate-950 pl-safe-island pr-safe-island pb-safe">
        <CockpitOverview
          quotas={quotas}
          selectedId={selectedId}
          onSelectPlatform={onSelect}
          onOpenDetail={handleOpenDetail}
          isOnline={isOnline}
          linkLabel={linkLabel}
          countdownSeconds={countdownSeconds}
          filterAlertOnly={filterAlertOnly}
          onToggleFilterAlert={onToggleFilterAlert}
          handedness={handedness}
        />
      </div>
    );
  }

  // ==========================================
  // 標準模式 B：iPhone Duo 雙欄自適應佈局 (38% : 62%)
  // ==========================================
  if (wide) {
    return (
      <div className="flex h-full w-full overflow-hidden bg-slate-950 pl-safe-island pr-safe-island">
        {/* 左欄 Master List (38% 黃金分割寬度，支援 Focus Mode 收折) */}
        <aside
          aria-label="AI 平台清單"
          className={`h-full transition-apple overflow-hidden ${
            isFocusMode
              ? 'w-0 opacity-0 pointer-events-none'
              : 'w-[38%] min-w-[280px] max-w-[420px] opacity-100'
          }`}
        >
          <MasterList
            quotas={quotas}
            selectedId={selectedId}
            onSelect={handleItemSelect}
            isLoading={isLoading}
          />
        </aside>

        {/* 右欄 Detail Workbench (62% 寬度或 100% 全寬) */}
        <main
          aria-label="AI 平台詳情與語音工作台"
          className="flex-1 h-full min-w-0 bg-slate-950"
        >
          <DetailWorkbench
            selectedItem={selectedItem}
            isFocusMode={isFocusMode}
            onToggleFocus={() => setIsFocusMode(!isFocusMode)}
            isVoiceActive={isVoiceActive}
            liveTranscript={liveTranscript}
            handedness={handedness}
            connectionLabel={linkLabel}
          />
        </main>
      </div>
    );
  }

  // ==========================================
  // 直向行動端單欄切換模式 (支援單手熱區)
  // ==========================================
  return (
    <div className="flex flex-col h-full w-full overflow-hidden bg-slate-950 pt-safe pb-safe">
      {showMobileDetail ? (
        <div className="flex flex-col h-full">
          <div className="p-3 border-b border-slate-800 flex items-center bg-slate-950">
            <button
              onClick={handleBack}
              className="flex items-center gap-1 text-sm font-semibold text-cyan-400 active:opacity-70 transition-all min-h-[44px] touch-manipulation"
            >
              <ChevronLeft className="w-5 h-5" />
              返回清單
            </button>
          </div>
          <div className="flex-1 overflow-y-auto">
            <DetailWorkbench
              selectedItem={selectedItem}
              isFocusMode={false}
              onToggleFocus={() => {}}
              isVoiceActive={isVoiceActive}
              liveTranscript={liveTranscript}
              handedness={handedness}
              connectionLabel={linkLabel}
            />
          </div>
        </div>
      ) : (
        <MasterList
          quotas={quotas}
          selectedId={selectedId}
          onSelect={handleItemSelect}
          isLoading={isLoading}
        />
      )}
    </div>
  );
};
