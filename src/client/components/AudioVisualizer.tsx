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
        // 靜默待機線條
        ctx.beginPath();
        ctx.moveTo(0, canvas.height / 2);
        ctx.lineTo(canvas.width, canvas.height / 2);
        ctx.strokeStyle = '#d2d2d7';
        ctx.lineWidth = 2;
        ctx.stroke();
        return;
      }

      // 60 FPS 動態音波渲染 (Swiss Minimal Blue)
      phase += 0.08;
      const centerY = canvas.height / 2;
      const amplitude = Math.min(30, Math.max(8, volume * 45));

      // 雙層波形增添層次
      [
        { color: 'rgba(0, 113, 227, 0.25)', speed: 1.2, width: 2 },
        { color: 'rgba(0, 113, 227, 0.85)', speed: 1.0, width: 2.5 },
      ].forEach((layer) => {
        ctx.beginPath();
        for (let x = 0; x < canvas.width; x++) {
          const y =
            centerY +
            Math.sin(x * 0.04 * layer.speed + phase) *
              amplitude *
              Math.sin((x / canvas.width) * Math.PI); // 兩端邊緣平滑收斂
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
    <div className="w-full flex flex-col items-center justify-center p-3 bg-white rounded-xl border border-[#e5e5ea] shadow-sm">
      <div className="flex items-center justify-between w-full mb-2">
        <span className="text-xs font-semibold text-[#86868b] tracking-wider uppercase">
          Gemini 3.8 Live 實時音訊波形
        </span>
        <span className="inline-flex items-center gap-1.5 text-xs font-medium">
          <span
            className={`w-2 h-2 rounded-full ${
              isActive ? 'bg-emerald-500 animate-pulse' : 'bg-gray-300'
            }`}
          />
          {isActive ? '即時通話中 (60 FPS)' : '休眠待命中'}
        </span>
      </div>
      <canvas
        ref={canvasRef}
        width={360}
        height={64}
        className="w-full h-16 rounded-lg bg-[#fbfbfd]"
      />
    </div>
  );
};
