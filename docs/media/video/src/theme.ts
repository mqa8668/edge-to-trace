import {loadFont} from '@remotion/google-fonts/Inter';
import {loadFont as loadMono} from '@remotion/google-fonts/JetBrainsMono';

export const {fontFamily: sans} = loadFont('normal', {weights: ['400', '600', '800']});
export const {fontFamily: mono} = loadMono('normal', {weights: ['400', '600']});

export const C = {
  bg: '#0a0e17',
  panel: '#121826',
  panelBorder: '#243049',
  text: '#e6eaf2',
  dim: '#8b97ad',
  teal: '#2dd4bf',
  blue: '#60a5fa',
  orange: '#f59e0b',
  red: '#f43f5e',
  green: '#4ade80',
};

export const FPS = 30;
export const W = 1920;
export const H = 1080;
