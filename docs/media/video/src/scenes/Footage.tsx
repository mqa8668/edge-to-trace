import React from 'react';
import {AbsoluteFill, interpolate, OffthreadVideo, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, mono, sans} from '../theme';
import type {Clip} from '../clips';

export const Footage: React.FC<{clip: Clip}> = ({clip}) => {
  const f = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const enter = spring({frame: f, fps, config: {damping: 200}});
  const cap = spring({frame: f - 10, fps, config: {damping: 18}});
  const out = interpolate(f, [durationInFrames - 8, durationInFrames], [1, 0], {extrapolateLeft: 'clamp'});
  return (
    <AbsoluteFill style={{background: C.bg, opacity: out}}>
      <div style={{position: 'absolute', inset: 0, background: `radial-gradient(1100px 600px at 50% 40%, ${C.blue}18, transparent 70%)`}} />
      <div
        style={{
          position: 'absolute', left: 80, top: 50, width: 1760, height: 990,
          borderRadius: 20, overflow: 'hidden', border: `2px solid ${C.panelBorder}`, background: C.panel,
          boxShadow: '0 30px 80px rgba(0,0,0,.6)', transform: `scale(${0.96 + 0.04 * enter})`, opacity: enter,
        }}
      >
        <OffthreadVideo src={staticFile(clip.file)} style={{width: 1760, height: 990, objectFit: 'cover'}} muted />
      </div>
      <div
        style={{
          position: 'absolute', left: 140, bottom: 90, padding: '22px 34px', borderRadius: 18,
          background: 'rgba(10,14,23,.88)', border: `1px solid ${C.panelBorder}`, backdropFilter: 'blur(6px)',
          transform: `translateY(${(1 - cap) * 40}px)`, opacity: cap, maxWidth: 1400,
        }}
      >
        <div style={{display: 'flex', alignItems: 'center', gap: 20}}>
          <div style={{fontFamily: mono, fontSize: 30, color: C.bg, background: C.teal, borderRadius: 10, padding: '2px 14px', fontWeight: 600}}>{clip.tag}</div>
          <div style={{fontFamily: sans, fontSize: 52, fontWeight: 800, color: C.text}}>{clip.caption}</div>
        </div>
        <div style={{fontFamily: sans, fontSize: 28, color: C.dim, marginTop: 8}}>{clip.sub}</div>
      </div>
    </AbsoluteFill>
  );
};
