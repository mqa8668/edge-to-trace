import React from 'react';
import {AbsoluteFill, Sequence} from 'remotion';
import {Architecture} from './scenes/Architecture';
import {Footage} from './scenes/Footage';
import {Outro} from './scenes/Outro';
import {Title} from './scenes/Title';
import {clips} from './clips';
import {FPS} from './theme';

export const TITLE = 4 * FPS;
export const ARCH = 330;
export const OUTRO = 6 * FPS;
export const total = () => TITLE + ARCH + clips.reduce((s, c) => s + c.seconds * FPS, 0) + OUTRO;

export const Video: React.FC = () => {
  let at = 0;
  const seq: React.ReactNode[] = [];
  seq.push(<Sequence key="t" from={at} durationInFrames={TITLE}><Title /></Sequence>);
  at += TITLE;
  seq.push(<Sequence key="a" from={at} durationInFrames={ARCH}><Architecture /></Sequence>);
  at += ARCH;
  clips.forEach((c, i) => {
    const d = c.seconds * FPS;
    seq.push(<Sequence key={`c${i}`} from={at} durationInFrames={d}><Footage clip={c} /></Sequence>);
    at += d;
  });
  seq.push(<Sequence key="o" from={at} durationInFrames={OUTRO}><Outro /></Sequence>);
  return <AbsoluteFill>{seq}</AbsoluteFill>;
};
