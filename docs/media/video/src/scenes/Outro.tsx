import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, mono, sans} from '../theme';

export const Outro: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const a = spring({frame: f, fps, config: {damping: 200}});
  const cmd = 'make demo';
  const typed = Math.min(cmd.length, Math.max(0, Math.floor((f - 25) / 3)));
  const b = spring({frame: f - 70, fps, config: {damping: 200}});
  const fadeIn = interpolate(f, [0, 10], [0, 1], {extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill style={{background: C.bg, justifyContent: 'center', alignItems: 'center', opacity: fadeIn}}>
      <div style={{position: 'absolute', inset: 0, background: `radial-gradient(900px 500px at 50% 50%, ${C.teal}20, transparent 70%)`}} />
      <div style={{fontFamily: sans, fontSize: 64, fontWeight: 800, color: C.text, opacity: a, transform: `translateY(${(1 - a) * 20}px)`}}>
        Run the whole story on your laptop
      </div>
      <div style={{marginTop: 50, padding: '28px 56px', borderRadius: 18, background: C.panel, border: `2px solid ${C.panelBorder}`, fontFamily: mono, fontSize: 84, color: C.text}}>
        <span style={{color: C.teal}}>$ </span>
        {cmd.slice(0, typed)}
        <span style={{color: C.teal, opacity: Math.floor(f / 12) % 2 === 0 ? 1 : 0}}>_</span>
      </div>
      <div style={{fontFamily: sans, fontSize: 34, color: C.dim, marginTop: 44, opacity: b}}>
        Docker Compose. About 4 GiB. SLO alert to exact span in minutes.
      </div>
      <div style={{fontFamily: mono, fontSize: 28, color: C.teal, marginTop: 28, opacity: b}}>edge-to-trace</div>
    </AbsoluteFill>
  );
};
