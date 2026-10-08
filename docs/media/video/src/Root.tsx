import React from 'react';
import {Composition} from 'remotion';
import {Video, total} from './Video';
import {FPS, H, W} from './theme';

export const Root: React.FC = () => (
  <Composition id="Main" component={Video} durationInFrames={total()} fps={FPS} width={W} height={H} />
);
