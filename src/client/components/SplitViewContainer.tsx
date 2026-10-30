import React, { useState, useEffect } from 'react';
import { MasterList } from './MasterList';
import { DetailWorkbench } from './DetailWorkbench';
import { QuotaCardProps } from './QuotaCard';
import { ChevronLeft } from 'lucide-react';

interface SplitViewContainerProps {
  quotas: QuotaCardProps[];
  selectedId: string;
  onSelect: (id: string) => void;
  isLoading: boolean;
  isVoiceActive: boolean;
  liveTranscript: string;
}

export const SplitViewContainer: React.FC<SplitViewContainerProps> = ({
  quotas,
  selectedId,
  onSelect,
  isLoading,
  isVoiceActive,
  liveTranscript,
}) => {
  const [isLandscape, setIsLandscape] = useState<boolean>(true);
  const [isFocusMode, setIsFocusMode] = useState<boolean>(false);
  const [showMobileDetail, setShowMobileDetail] = useState<boolean>(false);

  // 監聽螢幕方向與尺寸變化 (Apple HIG 橫向視窗判定)
  useEffect(() => {
    const checkOrientation = () => {
      const isWide = window.innerWidth >= 768 || (window.innerWidth > window.innerHeight && window.innerWidth >= 640);
      setIsLandscape(isWide);
    };

    checkOrientation();
    window.addEventListener('resize', checkOrientation);
    window.addEventListener('orientationchange', checkOrientation);

    return () => {
      window.removeEventListener('resize', checkOrientation);
      window.removeEventListener('orientationchange', checkOrientation);
    };
  }, []);

  // URL 深度連結同步 (State Restoration)
  useEffect(() => {
    if (typeof window !== 'undefined' && selectedId) {
      const url = new URL(window.location.href);
      url.searchParams.set('provider', selectedId);
      if (isLandscape) url.searchParams.set('duo', '1');
      window.history.replaceState({}, '', url.toString());
    }
  }, [selectedId, isLandscape]);

  const handleItemSelect = (id: string) => {
    onSelect(id);
    if (!isLandscape) {
      setShowMobileDetail(true);
    }
  };

  const selectedItem = quotas.find((q) => q.id === selectedId);

  // 橫向 iPhone Duo 雙欄自適應佈局 (38% : 62%)
  if (isLandscape) {
    return (
      <div className="flex h-screen w-screen overflow-hidden bg-[#f5f5f7] pl-safe-island pr-safe-island">
        {/* 左欄 Master List (38% 黃金分割寬度，支援 Focus Mode 收折) */}
        <aside
          aria-label="AI 平台清單"
          className={`h-full transition-apple overflow-hidden ${
            isFocusMode ? 'w-0 opacity-0 pointer-events-none' : 'w-[38%] min-w-[280px] max-w-[420px] opacity-100'
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
          className="flex-1 h-full min-w-0 bg-white"
        >
          <DetailWorkbench
            selectedItem={selectedItem}
            isFocusMode={isFocusMode}
            onToggleFocus={() => setIsFocusMode(!isFocusMode)}
            isVoiceActive={isVoiceActive}
            liveTranscript={liveTranscript}
          />
        </main>
      </div>
    );
  }

  // 直向行動端單欄切換模式
  return (
    <div className="flex flex-col h-screen w-screen overflow-hidden bg-white pt-safe pb-safe">
      {showMobileDetail ? (
        <div className="flex flex-col h-full">
          <div className="p-3 border-b border-[#e5e5ea] flex items-center">
            <button
              onClick={() => setShowMobileDetail(false)}
              className="flex items-center gap-1 text-sm font-semibold text-[#0071e3] active:opacity-70 transition-all"
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
