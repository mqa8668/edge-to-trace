import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, mono, sans} from '../theme';

export const Title: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const word = 'edge-to-trace';
  const typed = Math.min(word.length, Math.floor(f / 2.2));
  const cursorOn = Math.floor(f / 12) % 2 === 0 || typed < word.length;
  const sub = spring({frame: f - 40, fps, config: {damping: 200}});
  const line = spring({frame: f - 20, fps, config: {damping: 200}});
  const fade = interpolate(f, [100, 120], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill style={{background: C.bg, justifyContent: 'center', alignItems: 'center', opacity: fade}}>
      <div style={{position: 'absolute', inset: 0, background: `radial-gradient(900px 500px at 50% 45%, ${C.teal}22, transparent 70%)`}} />
      <div style={{fontFamily: mono, fontSize: 150, fontWeight: 600, color: C.text, letterSpacing: -4}}>
        {word.slice(0, typed)}
        <span style={{color: C.teal, opacity: cursorOn ? 1 : 0}}>_</span>
      </div>
      <div style={{width: 760 * line, height: 4, background: `linear-gradient(90deg, ${C.teal}, ${C.blue})`, borderRadius: 2, marginTop: 24}} />
      <div style={{fontFamily: sans, fontSize: 44, color: C.dim, marginTop: 34, opacity: sub, transform: `translateY(${(1 - sub) * 20}px)`}}>
        From a page to the exact slow span
      </div>
    </AbsoluteFill>
  );
};
