import React, { useState, useEffect, useRef } from 'react';
import { SplitViewContainer } from './components/SplitViewContainer';
import { FloatingActionToolbar } from './components/FloatingActionToolbar';
import { ModelSyncModal } from './components/ModelSyncModal';
import { QuotaCardProps } from './components/QuotaCard';

export const App: React.FC = () => {
  const [quotas, setQuotas] = useState<QuotaCardProps[]>([]);
  const [selectedId, setSelectedId] = useState<string>('cursor');
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isVoiceActive, setIsVoiceActive] = useState<boolean>(false);
  const [liveTranscript, setLiveTranscript] = useState<string>('');
  const [isModelModalOpen, setIsModelModalOpen] = useState<boolean>(false);
  const [isSyncing, setIsSyncing] = useState<boolean>(false);
  const [models, setModels] = useState<any[]>([]);

  const wsRef = useRef<WebSocket | null>(null);

  // 初始化載入 AI 平台額度
  useEffect(() => {
    fetchQuotas();
    fetchModels();
  }, []);

  const fetchQuotas = async () => {
    try {
      setIsLoading(true);
      const res = await fetch('/api/quotas');
      const data = await res.json();
      if (data.success && Array.isArray(data.data)) {
        const mapped: QuotaCardProps[] = data.data.map((item: any) => ({
          id: item.provider_id || item.id,
          name: item.name,
          planName: item.plan_name || 'Standard',
          totalQuota: item.total_quota || 100,
          usedQuota: item.used_quota || 0,
          remainingPercent: item.remaining_percent || 100,
          resetTime: item.reset_time || '每月重置',
          status: item.status || 'active',
        }));
        setQuotas(mapped);
      }
    } catch {
      // 本地展示預設值
      setQuotas([
        {
          id: 'cursor',
          name: 'Cursor',
          planName: 'Pro / Business',
          totalQuota: 500,
          usedQuota: 0,
          remainingPercent: 100,
          resetTime: '每月重置',
          status: 'active',
        },
        {
          id: 'grok',
          name: 'Grok',
          planName: 'SuperGrok',
          totalQuota: 100,
          usedQuota: 0,
          remainingPercent: 100,
          resetTime: '每週重置',
          status: 'active',
        },
        {
          id: 'antigravity',
          name: 'Antigravity (Gemini)',
          planName: 'Google AI Pro',
          totalQuota: 100,
          usedQuota: 34,
          remainingPercent: 66,
          resetTime: '今天 2:29 重置',
          status: 'active',
        },
        {
          id: 'claude',
          name: 'Claude Code',
          planName: 'Team Pro',
          totalQuota: 100,
          usedQuota: 28,
          remainingPercent: 72,
          resetTime: '今天 5:06 重置',
          status: 'active',
        },
      ]);
    } finally {
      setIsLoading(false);
    }
  };

  const fetchModels = async () => {
    try {
      const res = await fetch('/api/models/sync', { method: 'POST' });
      const data = await res.json();
      if (data.success && Array.isArray(data.models)) {
        setModels(data.models);
        return;
      }
    } catch {}

    // 本地離線/預覽預設模型清單
    setModels([
      {
        id: 'gemini-3.8-live',
        name: 'Gemini 3.8 Live (Audio & Vision)',
        provider: 'Google',
        context_window: 2000000,
        supports_live: true,
        supports_thinking: true,
        thinking_budget_max: 32768,
        cost_per_m_input: 0.125,
        cost_per_m_output: 0.5,
      },
      {
        id: 'gemini-3.8-flash',
        name: 'Gemini 3.8 Flash (High Reasoning)',
        provider: 'Google',
        context_window: 1000000,
        supports_live: false,
        supports_thinking: true,
        thinking_budget_max: 65536,
        cost_per_m_input: 0.075,
        cost_per_m_output: 0.3,
      },
      {
        id: 'grok-4.5',
        name: 'Grok 4.5 Full Reasoning',
        provider: 'xAI',
        context_window: 128000,
        supports_live: false,
        supports_thinking: true,
        thinking_budget_max: 16384,
        cost_per_m_input: 0.5,
        cost_per_m_output: 2.0,
      },
      {
        id: 'claude-3-7-sonnet',
        name: 'Claude 3.7 Sonnet (Hybrid Thinking)',
        provider: 'Anthropic',
        context_window: 200000,
        supports_live: false,
        supports_thinking: true,
        thinking_budget_max: 64000,
        cost_per_m_input: 3.0,
        cost_per_m_output: 15.0,
      },
      {
        id: 'cursor-fast',
        name: 'Cursor Composer (Fast Edit)',
        provider: 'Cursor',
        context_window: 128000,
        supports_live: false,
        supports_thinking: false,
        cost_per_m_input: 0.0,
        cost_per_m_output: 0.0,
      },
    ]);
  };

  const handleSyncModels = async () => {
    setIsSyncing(true);
    try {
      await fetchModels();
      setIsModelModalOpen(true);
    } finally {
      setIsSyncing(false);
    }
  };

  const toggleVoice = () => {
    if (isVoiceActive) {
      // 關閉語音
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
      setIsVoiceActive(false);
      setLiveTranscript('通話已結束。連線已休眠。');
    } else {
      // 開啟 Gemini 3.8 Live 雙向連線
      setIsVoiceActive(true);
      setLiveTranscript('正在建立 Cloudflare Durable Object 邊緣長連線...');

      try {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws/live?sessionId=user_session_${Date.now()}`;
        const ws = new WebSocket(wsUrl);
        wsRef.current = ws;

        ws.onopen = () => {
          setLiveTranscript('Gemini 3.8 Live API 已就緒。請說話（例如：「查詢 Cursor 目前剩餘額度」）...');
        };

        ws.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);
            if (data.serverContent?.modelTurn?.parts) {
              const textParts = data.serverContent.modelTurn.parts
                .map((p: any) => p.text || '')
                .join('');
              if (textParts) {
                setLiveTranscript((prev) => `${prev}\nGemini: ${textParts}`);
              }
            }
          } catch {
            setLiveTranscript(`Gemini Live: ${event.data}`);
          }
        };

        ws.onerror = () => {
          setLiveTranscript('連線至 Gemini Live 服務中斷，已啟動自動休眠防護。');
        };

        ws.onclose = () => {
          setIsVoiceActive(false);
        };
      } catch (err: any) {
        setLiveTranscript(`連線失敗: ${err.message}`);
        setIsVoiceActive(false);
      }
    }
  };

  return (
    <div className="relative w-screen h-screen overflow-hidden">
      <SplitViewContainer
        quotas={quotas}
        selectedId={selectedId}
        onSelect={setSelectedId}
        isLoading={isLoading}
        isVoiceActive={isVoiceActive}
        liveTranscript={liveTranscript}
      />

      <FloatingActionToolbar
        isVoiceActive={isVoiceActive}
        isSyncing={isSyncing}
        onToggleVoice={toggleVoice}
        onSyncModels={handleSyncModels}
      />

      <ModelSyncModal
        isOpen={isModelModalOpen}
        onClose={() => setIsModelModalOpen(false)}
        models={models}
        isSyncing={isSyncing}
        onTriggerSync={fetchModels}
      />
    </div>
  );
};

export default App;
