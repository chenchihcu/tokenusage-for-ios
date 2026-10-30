export interface DiscoveredModel {
  id: string;
  name: string;
  provider: 'Cursor' | 'OpenAI' | 'Google' | 'Anthropic' | 'xAI';
  contextWindow: number;
  supportsLive: boolean;
  supportsThinking: boolean;
  thinkingBudgetMax?: number;
  costPerMInput: number;
  costPerMOutput: number;
  status: 'active';
  verifiedDate: string;
}

const SSRF_ALLOWED_DOMAINS = [
  'generativelanguage.googleapis.com',
  'api.openai.com',
  'api.x.ai',
  'api.anthropic.com',
  'api2.cursor.sh',
];

const DEPRECATED_MODEL_PATTERNS = [
  /gpt-3\.5/i,
  /davinci/i,
  /claude-[12]/i,
  /gemini-1\.0/i,
  /gpt-4-0[36]1[34]/i,
  /babbage/i,
  /curie/i,
  /ada/i,
];

export function validateUpstreamUrl(targetUrl: string): boolean {
  try {
    const url = new URL(targetUrl);
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

export function filterOutDeprecated(models: DiscoveredModel[]): DiscoveredModel[] {
  return models.filter(m => {
    return !DEPRECATED_MODEL_PATTERNS.some(p => p.test(m.id) || p.test(m.name));
  });
}

export async function discoverLatestModels(forceRefresh = false): Promise<DiscoveredModel[]> {
  const models: DiscoveredModel[] = [
    // OpenAI (Codex / ChatGPT)
    {
      id: 'gpt-6.1-sol',
      name: 'GPT-6.1 Sol (Workhorse Coding)',
      provider: 'OpenAI',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 32768,
      costPerMInput: 1.25,
      costPerMOutput: 5.0,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'gpt-6-astra',
      name: 'GPT-6 Astra (Frontier Intelligence)',
      provider: 'OpenAI',
      contextWindow: 200000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 65536,
      costPerMInput: 2.5,
      costPerMOutput: 10.0,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'o3-mini',
      name: 'OpenAI o3-mini (High Reasoning 100K)',
      provider: 'OpenAI',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 100000,
      costPerMInput: 1.10,
      costPerMOutput: 4.40,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'gpt-4o-latest',
      name: 'GPT-4o (Omni Multimodal Flagship)',
      provider: 'OpenAI',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: false,
      costPerMInput: 2.50,
      costPerMOutput: 10.00,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    // Google (Antigravity)
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
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'gemini-3.8-live',
      name: 'Gemini 3.8 Live (Audio & Vision Stream)',
      provider: 'Google',
      contextWindow: 2000000,
      supportsLive: true,
      supportsThinking: true,
      thinkingBudgetMax: 32768,
      costPerMInput: 0.125,
      costPerMOutput: 0.5,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'gemini-2.5-pro',
      name: 'Gemini 2.5 Pro (Deep Code & Context)',
      provider: 'Google',
      contextWindow: 1000000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 32768,
      costPerMInput: 1.25,
      costPerMOutput: 5.0,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'gemini-2.5-flash',
      name: 'Gemini 2.5 Flash (Agile Workhorse)',
      provider: 'Google',
      contextWindow: 1000000,
      supportsLive: false,
      supportsThinking: false,
      costPerMInput: 0.075,
      costPerMOutput: 0.3,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    // Anthropic (Claude Code)
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
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'claude-3-5-sonnet',
      name: 'Claude 3.5 Sonnet (Frontier Coding)',
      provider: 'Anthropic',
      contextWindow: 200000,
      supportsLive: false,
      supportsThinking: false,
      costPerMInput: 3.0,
      costPerMOutput: 15.0,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'claude-3-5-haiku',
      name: 'Claude 3.5 Haiku (Fast Agent)',
      provider: 'Anthropic',
      contextWindow: 200000,
      supportsLive: false,
      supportsThinking: false,
      costPerMInput: 0.8,
      costPerMOutput: 4.0,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'claude-fable-5-1',
      name: 'Claude Fable 5.1 (Long-Running Agent)',
      provider: 'Anthropic',
      contextWindow: 1000000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 64000,
      costPerMInput: 4.0,
      costPerMOutput: 20.0,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    // xAI (Grok - bonded with Cursor)
    {
      id: 'grok-4.5',
      name: 'Grok 4.5 Full Reasoning',
      provider: 'xAI',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 32768,
      costPerMInput: 0.5,
      costPerMOutput: 2.0,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'grok-3',
      name: 'Grok 3 Frontier',
      provider: 'xAI',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: false,
      costPerMInput: 0.5,
      costPerMOutput: 2.0,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    // Cursor
    {
      id: 'cursor-fast',
      name: 'Cursor Composer (Fast Edit)',
      provider: 'Cursor',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: false,
      costPerMInput: 0.0,
      costPerMOutput: 0.0,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
    {
      id: 'cursor-agent',
      name: 'Cursor Autonomous Agent',
      provider: 'Cursor',
      contextWindow: 128000,
      supportsLive: false,
      supportsThinking: true,
      thinkingBudgetMax: 32768,
      costPerMInput: 0.0,
      costPerMOutput: 0.0,
      status: 'active',
      verifiedDate: '2026-10-30',
    },
  ];

  return filterOutDeprecated(models);
}
