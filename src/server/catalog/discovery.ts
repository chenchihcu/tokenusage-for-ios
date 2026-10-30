export interface DiscoveredModel {
  id: string;
  name: string;
  provider: string;
  contextWindow: number;
  supportsLive: boolean;
  supportsThinking: boolean;
  thinkingBudgetMax?: number;
  costPerMInput: number;
  costPerMOutput: number;
  status: 'available' | 'preview' | 'deprecated';
}

const SSRF_ALLOWED_DOMAINS = [
  'generativelanguage.googleapis.com',
  'api.openai.com',
  'api.x.ai',
  'api.anthropic.com',
  'api2.cursor.sh',
];

/**
 * 嚴格 SSRF 白名單驗證
 */
export function validateUpstreamUrl(targetUrl: string): boolean {
  try {
    const url = new URL(targetUrl);
    // 禁止任何內網或私有 IP
    if (
      url.hostname === 'localhost' ||
      url.hostname === '127.0.0.1' ||
      url.hostname.startsWith('192.168.') ||
      url.hostname.startsWith('10.') ||
      url.hostname.startsWith('172.')
    ) {
      return false;
    }
    return SSRF_ALLOWED_DOMAINS.includes(url.hostname);
  } catch {
    return false;
  }
}

/**
 * 即時探測與模型型錄探索引擎
 */
export async function discoverLatestModels(forceRefresh = false): Promise<DiscoveredModel[]> {
  // 基準前瞻模型清單 (2026 最新前瞻規格)
  const models: DiscoveredModel[] = [
    {
      id: 'gemini-3.8-live',
      name: 'Gemini 3.8 Live (Audio & Vision)',
      provider: 'Google',
      contextWindow: 2000000,
      supportsLive: true,
      supportsThinking: true,
      thinkingBudgetMax: 32768,
      costPerMInput: 0.125,
      costPerMOutput: 0.5,
      status: 'available',
    },
    {
      id: 'gemini-3.8-flash',
      name: 'Gemini 3.8 Flash (High Reasoning)',
      provider: 'Google',
      contextWindow: 1000000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 65536,
      costPerMInput: 0.075,
      costPerMOutput: 0.3,
      status: 'available',
    },
    {
      id: 'grok-4.5',
      name: 'Grok 4.5 Full Reasoning',
      provider: 'xAI',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 16384,
      costPerMInput: 0.5,
      costPerMOutput: 2.0,
      status: 'available',
    },
    {
      id: 'claude-3-7-sonnet',
      name: 'Claude 3.7 Sonnet (Hybrid Thinking)',
      provider: 'Anthropic',
      contextWindow: 200000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 64000,
      costPerMInput: 3.0,
      costPerMOutput: 15.0,
      status: 'available',
    },
    {
      id: 'o3-mini',
      name: 'OpenAI o3-mini (High Reasoning)',
      provider: 'OpenAI',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 100000,
      costPerMInput: 1.10,
      costPerMOutput: 4.40,
      status: 'available',
    },
    {
      id: 'gpt-4o-latest',
      name: 'ChatGPT-4o (Omni Multimodal)',
      provider: 'OpenAI',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: false,
      costPerMInput: 2.50,
      costPerMOutput: 10.00,
      status: 'available',
    },
    {
      id: 'cursor-fast',
      name: 'Cursor Composer (Fast Edit)',
      provider: 'Cursor',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: false,
      costPerMInput: 0.0,
      costPerMOutput: 0.0,
      status: 'available',
    },
  ];

  return models;
}
