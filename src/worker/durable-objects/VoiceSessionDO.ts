import { Env, ProviderQuotaRecord } from '../env';

export class VoiceSessionDO {
  state: DurableObjectState;
  env: Env;
  upstreamWs: WebSocket | null = null;
  sessionId: string;

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
    this.sessionId = state.id.toString();
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/ws') {
      const upgradeHeader = request.headers.get('Upgrade');
      if (!upgradeHeader || upgradeHeader.toLowerCase() !== 'websocket') {
        return new Response('Expected Upgrade: websocket', { status: 426 });
      }

      // 建立 WebSocket Pair (Client <-> Durable Object)
      const webSocketPair = new WebSocketPair();
      const [clientWs, serverWs] = Object.values(webSocketPair);

      // 啟用 Cloudflare WebSocket Hibernation API
      this.state.acceptWebSocket(serverWs);

      // 初始化上游 Gemini 3.8 Live API 連線
      const apiKey = this.env.GEMINI_API_KEY || '';
      if (apiKey) {
        this.initUpstreamLive(apiKey, serverWs);
      }

      return new Response(null, {
        status: 101,
        webSocket: clientWs,
      });
    }

    return new Response('Not Found', { status: 404 });
  }

  // 接收用戶端訊息 (由 Hibernation 邊緣架構即時喚醒)
  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    try {
      if (typeof message === 'string') {
        const data = JSON.parse(message);

        // 處理自訂指令或 API Key 注入
        if (data.type === 'init' && data.apiKey) {
          await this.initUpstreamLive(data.apiKey, ws);
          return;
        }

        // 處理工具調用回覆或文字輸入
        if (this.upstreamWs && this.upstreamWs.readyState === WebSocket.OPEN) {
          this.upstreamWs.send(message);
        }
      } else {
        // 傳輸 PCM 16kHz 二進位音訊 Chunk 給 Gemini Live
        if (this.upstreamWs && this.upstreamWs.readyState === WebSocket.OPEN) {
          const base64Audio = btoa(
            String.fromCharCode(...new Uint8Array(message))
          );
          const payload = {
            realtimeInput: {
              mediaChunks: [
                {
                  mimeType: 'audio/pcm;rate=16000',
                  data: base64Audio,
                },
              ],
            },
          };
          this.upstreamWs.send(JSON.stringify(payload));
        }
      }
    } catch (err: any) {
      ws.send(JSON.stringify({ type: 'error', error: err.message }));
    }
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean) {
    if (this.upstreamWs) {
      try {
        this.upstreamWs.close();
      } catch {}
      this.upstreamWs = null;
    }
  }

  async webSocketError(ws: WebSocket, error: any) {
    if (this.upstreamWs) {
      try {
        this.upstreamWs.close();
      } catch {}
      this.upstreamWs = null;
    }
  }

  private async initUpstreamLive(apiKey: string, clientWs: WebSocket) {
    try {
      const liveEndpoint = `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=${apiKey}`;
      const upstream = new WebSocket(liveEndpoint);
      this.upstreamWs = upstream;

      upstream.addEventListener('open', () => {
        // 發送初始化 Setup 協議（配置 Gemini 3.8 Live 模型與工具呼叫）
        const setupMessage = {
          setup: {
            model: 'models/gemini-2.0-flash-exp', // 相容 live protocol 之最新語音模型
            generationConfig: {
              responseModalities: ['AUDIO'],
              speechConfig: {
                voiceConfig: {
                  prebuiltVoiceConfig: {
                    voiceName: 'Puck', // 高清晰度語音
                  },
                },
              },
            },
            tools: [
              {
                functionDeclarations: [
                  {
                    name: 'get_provider_quota',
                    description: '查詢特定 AI 平台目前的額度、剩餘百分比與重置時間',
                    parameters: {
                      type: 'OBJECT',
                      properties: {
                        provider: {
                          type: 'STRING',
                          description: 'AI 平台識別碼，例如 cursor, grok, claude, antigravity',
                        },
                      },
                      required: ['provider'],
                    },
                  },
                ],
              },
            ],
          },
        };
        upstream.send(JSON.stringify(setupMessage));
        clientWs.send(JSON.stringify({ type: 'ready', sessionId: this.sessionId }));
      });

      upstream.addEventListener('message', async (event) => {
        const raw = typeof event.data === 'string' ? event.data : new TextDecoder().decode(event.data);
        const parsed = JSON.parse(raw);

        // 檢查是否包含工具調用 (Tool Call)
        if (parsed.serverContent && parsed.serverContent.modelTurn) {
          const parts = parsed.serverContent.modelTurn.parts || [];
          for (const part of parts) {
            if (part.functionCall) {
              const call = part.functionCall;
              if (call.name === 'get_provider_quota') {
                const provider = call.args?.provider || 'cursor';
                const quota = await this.queryD1Quota(provider);
                
                // 回覆工具調用結果給 Gemini
                const toolResponse = {
                  toolResponse: {
                    functionResponses: [
                      {
                        response: { output: quota },
                        id: call.id,
                      },
                    ],
                  },
                };
                upstream.send(JSON.stringify(toolResponse));
              }
            }
          }
        }

        // 即時轉發給客戶端
        clientWs.send(raw);
      });

      upstream.addEventListener('close', () => {
        clientWs.send(JSON.stringify({ type: 'upstream_closed' }));
      });

      upstream.addEventListener('error', (err: any) => {
        clientWs.send(JSON.stringify({ type: 'upstream_error', error: String(err) }));
      });
    } catch (e: any) {
      clientWs.send(JSON.stringify({ type: 'upstream_connect_failed', error: e.message }));
    }
  }

  private async queryD1Quota(providerId: string): Promise<ProviderQuotaRecord | null> {
    try {
      const stmt = this.env.DB.prepare(
        'SELECT * FROM provider_quotas WHERE provider_id = ? LIMIT 1'
      );
      const res = await stmt.bind(providerId).first<ProviderQuotaRecord>();
      return res || null;
    } catch (e) {
      return null;
    }
  }
}
