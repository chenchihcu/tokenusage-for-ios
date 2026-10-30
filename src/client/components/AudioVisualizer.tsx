import React, { useEffect, useRef } from 'react';

interface AudioVisualizerProps {
  isActive: boolean;
  volume?: number;
}

export const AudioVisualizer: React.FC<AudioVisualizerProps> = ({ isActive, volume = 0.5 }) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animationFrameId: number;
    let phase = 0;

    const render = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      if (!isActive) {
        // 待機冷靜線條
        ctx.beginPath();
        ctx.moveTo(0, canvas.height / 2);
        ctx.lineTo(canvas.width, canvas.height / 2);
        ctx.strokeStyle = 'rgba(148, 163, 184, 0.2)';
        ctx.lineWidth = 2;
        ctx.stroke();
        return;
      }

      // 60 FPS 霓虹動態音波渲染
      phase += 0.08;
      const centerY = canvas.height / 2;
      const amplitude = Math.min(30, Math.max(8, volume * 45));

      // 雙層霓虹色彩波形
      [
        { color: 'rgba(168, 85, 247, 0.4)', speed: 1.2, width: 2 },
        { color: 'rgba(0, 242, 254, 0.9)', speed: 1.0, width: 2.5 },
      ].forEach((layer) => {
        ctx.beginPath();
        for (let x = 0; x < canvas.width; x++) {
          const y =
            centerY +
            Math.sin(x * 0.04 * layer.speed + phase) *
              amplitude *
              Math.sin((x / canvas.width) * Math.PI);
          if (x === 0) {
            ctx.moveTo(x, y);
          } else {
            ctx.lineTo(x, y);
          }
        }
        ctx.strokeStyle = layer.color;
        ctx.lineWidth = layer.width;
        ctx.stroke();
      });

      animationFrameId = requestAnimationFrame(render);
    };

    render();

    return () => {
      cancelAnimationFrame(animationFrameId);
    };
  }, [isActive, volume]);

  return (
    <div className="w-full flex flex-col items-center justify-center p-3.5 glass-panel rounded-2xl border border-slate-800/80 shadow-lg">
      <div className="flex items-center justify-between w-full mb-2">
        <span className="text-xs font-semibold text-slate-400 tracking-wider uppercase font-mono">
          Gemini 3.8 Live 實時音訊波形
        </span>
        <span className="inline-flex items-center gap-1.5 text-xs font-medium">
          <span
            className={`w-2 h-2 rounded-full ${
              isActive ? 'bg-cyan-400 animate-pulse' : 'bg-slate-700'
            }`}
          />
          <span className={isActive ? 'text-cyan-300 font-mono font-semibold' : 'text-slate-500'}>
            {isActive ? '即時通話中 (60 FPS)' : '休眠待命中'}
          </span>
        </span>
      </div>
      <canvas
        ref={canvasRef}
        width={360}
        height={64}
        className="w-full h-16 rounded-xl bg-slate-950/80 border border-slate-900"
      />
    </div>
  );
};
