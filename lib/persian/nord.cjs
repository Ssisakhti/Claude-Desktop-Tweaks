'use strict';

// Official palette: https://www.nordtheme.com/docs/colors-and-palettes/
// Error and success text colors are brighter for small-text contrast.
const NORD = Object.freeze({
  nord0: '#2e3440', nord1: '#3b4252', nord2: '#434c5e', nord3: '#4c566a',
  nord4: '#d8dee9', nord5: '#e5e9f0', nord6: '#eceff4', nord7: '#8fbcbb',
  nord8: '#88c0d0', nord9: '#81a1c1', nord10: '#5e81ac', nord11: '#bf616a',
  nord12: '#d08770', nord13: '#ebcb8b', nord14: '#a3be8c', nord15: '#b48ead',
});

// Gruvbox Dark, hard contrast. Official palette: https://github.com/morhetz/gruvbox
const GRUVBOX = Object.freeze({
 nord0:'#1d2021',nord1:'#282828',nord2:'#3c3836',nord3:'#665c54',
 nord4:'#d5c4a1',nord5:'#ebdbb2',nord6:'#fbf1c7',nord7:'#fe8019',
 nord8:'#fabd2f',nord9:'#928374',nord10:'#d79921',nord11:'#fb4934',
 nord12:'#fe8019',nord13:'#fabd2f',nord14:'#b8bb26',nord15:'#d3869b',
});
function createTheme(NORD) {

function mix(base, tint, fraction) {
  const a = base.slice(1).match(/../g).map(value => parseInt(value, 16));
  const b = tint.slice(1).match(/../g).map(value => parseInt(value, 16));
  return '#' + a.map((value, i) => Math.round(value * (1 - fraction) + b[i] * fraction).toString(16).padStart(2, '0')).join('');
}

// Interaction fills can be painted above content by CDS layer utilities.
const OVERLAYS = Object.freeze({ subtle: NORD.nord6 + '0d', neutral: NORD.nord6 + '1a', hover: NORD.nord6 + '13', secondaryHover: NORD.nord6 + '24', selected: NORD.nord6 + '26', control: NORD.nord6 + '33', card: NORD.nord6 + '08' });

const COLORS = Object.freeze({
  background: NORD.nord0, surface: NORD.nord1, hover: NORD.nord1,
  selection: NORD.nord2, selectionText: NORD.nord6,
  promptSuggestion: mix(NORD.nord9, NORD.nord6, 0.30),
  text: NORD.nord6, textSecondary: NORD.nord5, textMuted: NORD.nord4,
  border: NORD.nord9, borderSubtle: NORD.nord3, focus: NORD.nord8, composerFocus: NORD.nord9,
  accent: NORD.nord8, accentText: mix(NORD.nord8, NORD.nord6, 0.15),
  accentHover: NORD.nord7, onAccent: NORD.nord0,
  error: NORD.nord11, errorText: mix(NORD.nord11, NORD.nord6, 0.60),
  errorBackground: mix(NORD.nord0, NORD.nord11, 0.18),
  success: NORD.nord14, successText: mix(NORD.nord14, NORD.nord6, 0.16),
  successBackground: mix(NORD.nord0, NORD.nord14, 0.14),
  warning: NORD.nord13, special: NORD.nord15,
});

function palette() { return COLORS; }

// window-shared.css variables accept HSL components without an hsl() function.
function hsl(hex) {
  const [r, g, b] = hex.slice(1).match(/../g).map(value => parseInt(value, 16) / 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
  const lightness = (max + min) / 2;
  let hue = 0, saturation = 0;
  if (delta) {
    saturation = delta / (1 - Math.abs(2 * lightness - 1));
    if (max === r) hue = ((g - b) / delta) % 6;
    else if (max === g) hue = (b - r) / delta + 2;
    else hue = (r - g) / delta + 4;
    hue = (hue * 60 + 360) % 360;
  }
  const round = value => Number(value.toFixed(3));
  return `${round(hue)} ${round(saturation * 100)}% ${round(lightness * 100)}%`;
}

// These token names were checked in the local Claude package about.html.
// CDS values are complete CSS colors, unlike the HSL components in older --bg-* tokens.
const CDS_COLORS = Object.freeze({
  '--cds-surface-0': COLORS.background,
  '--cds-page-bg': COLORS.background,
  '--cds-surface-1': COLORS.background,
  '--cds-surface-2': COLORS.surface,
  '--cds-surface-3': COLORS.hover,
  '--cds-surface-panel': COLORS.background,
  '--cds-surface-popover': COLORS.hover,
  '--cds-text-primary': COLORS.text,
  '--cds-text-secondary': COLORS.textSecondary,
  '--cds-text-muted': COLORS.textMuted,
  '--cds-text-stays-secondary': COLORS.textSecondary,
  '--cds-text-disabled': NORD.nord9,
  '--cds-text-accent': COLORS.accentText,
  '--cds-text-danger': COLORS.errorText,
  '--cds-text-success': COLORS.successText,
  '--cds-text-warning': COLORS.warning,
  '--cds-text-pro': NORD.nord15,
  '--cds-border': COLORS.borderSubtle,
  '--cds-border-line': COLORS.borderSubtle,
  '--cds-border-line-muted': NORD.nord3 + 'b3',
  '--cds-tooltip-bg': COLORS.surface,
  '--cds-tooltip-fg': COLORS.text,
  '--cds-border-strong': COLORS.border,
  '--cds-border-stronger': COLORS.focus,
  '--cds-border-accent': COLORS.focus,
  '--cds-border-danger': COLORS.errorText,
  '--cds-border-success': COLORS.successText,
  '--cds-border-warning': COLORS.warning,
  '--cds-fill-primary': COLORS.text,
  '--cds-fill-primary-hover': COLORS.textSecondary,
  '--cds-on-primary': COLORS.background,
  '--cds-fill-secondary': OVERLAYS.neutral,
  '--cds-fill-secondary-hover': OVERLAYS.secondaryHover,
  '--cds-fill-control': OVERLAYS.neutral,
  '--cds-fill-control-hover': OVERLAYS.control,
  '--cds-fill-field': OVERLAYS.subtle,
  '--cds-fill-card': OVERLAYS.card,
  '--cds-fill-card-hover': OVERLAYS.subtle,
  '--cds-fill-field-ring': COLORS.focus,
  '--cds-fill-ghost-hover': OVERLAYS.hover,
  '--cds-fill-ghost-selected': OVERLAYS.selected,
  '--cds-fill-button-ghost-hover': OVERLAYS.selected,
  '--cds-fill-accent': COLORS.accent,
  '--cds-fill-accent-hover': COLORS.accentHover,
  '--cds-on-accent': COLORS.onAccent,
  '--cds-fill-brand': COLORS.accent,
  '--cds-fill-brand-hover': COLORS.accentHover,
  '--cds-on-brand': COLORS.onAccent,
  '--cds-fill-danger': COLORS.errorText,
  '--cds-fill-danger-hover': COLORS.errorText,
  '--cds-on-danger': COLORS.onAccent,
  '--cds-fill-success': COLORS.successText,
  '--cds-fill-success-hover': COLORS.successText,
  '--cds-on-success': COLORS.onAccent,
  '--cds-bg-neutral': OVERLAYS.subtle,
  '--cds-bg-neutral-hover': OVERLAYS.neutral,
  '--cds-bg-neutral-chip': OVERLAYS.neutral,
  '--cds-bg-neutral-chip-hover': OVERLAYS.selected,
  '--cds-bg-accent': COLORS.surface,
  '--cds-bg-danger': COLORS.errorBackground,
  '--cds-bg-success': COLORS.successBackground,
  '--cds-bg-highlight': COLORS.selection,
  '--cds-bg-user-message': COLORS.surface,
  '--cds-bg-user-message-personal': COLORS.surface,
  '--cds-bg-editor-canvas': COLORS.background,
});

// Accept allowlisted names only. Do not infer a token from a substring.
function nordComputedOverrides(properties) {
  const names = properties && typeof properties[Symbol.iterator] === 'function'
    ? Array.from(properties) : Object.keys(properties || {});
  return Object.fromEntries(names.filter(name => typeof name === 'string' &&
    Object.hasOwn(CDS_COLORS, name)).map(name => [name, CDS_COLORS[name]]));
}

const DARK_SCOPE = ':is(.darkTheme,html.dark,html[data-theme="dark"],html[data-color-mode="dark"],html[data-mode="dark"])';

function nordThemeCss({ forceDark = false } = {}) {
  // Use forceDark only for a frame whose dark mode the caller has verified.
  // This function changes no DOM markers or system settings.
  const scope = forceDark ? ':is(:root,.cds-root)' : DARK_SCOPE;
  const rootScope = forceDark ? ':root' : DARK_SCOPE;
  const c = palette();
  const variables = {
    '--bg-000': c.background, '--bg-100': c.background, '--bg-200': c.surface,
    '--bg-300': c.hover, '--bg-400': c.borderSubtle, '--bg-500': c.borderSubtle,
    '--text-000': c.text, '--text-100': c.text, '--text-200': c.textSecondary,
    '--text-300': c.textSecondary, '--text-400': c.textMuted, '--text-500': c.textMuted,
    '--border-100': c.border, '--border-200': c.border,
    '--border-300': c.border, '--border-400': c.border,
    '--accent-brand': c.accent, '--brand-000': c.accentText, '--brand-100': c.accent,
    '--brand-200': c.accentHover, '--brand-900': c.surface,
    '--accent-000': c.accentText, '--accent-100': c.accent, '--accent-200': c.accentHover,
    '--accent-900': c.surface,
    '--accent-pro-000': c.special, '--accent-pro-100': c.special,
    '--accent-pro-200': c.special, '--accent-pro-900': c.surface,
    '--danger-000': c.errorText, '--danger-100': c.errorText,
    '--danger-200': c.errorText, '--danger-900': c.errorBackground,
    '--success-000': c.successText, '--success-100': c.successText,
    '--success-200': c.successText, '--success-900': c.successBackground,
    '--oncolor-100': c.onAccent, '--oncolor-200': c.onAccent, '--oncolor-300': c.onAccent,
    '--nord-hover-background': c.hover, '--nord-selection-background': c.selection,
    '--nord-selection-text': c.selectionText, '--nord-focus': c.focus,
    '--nord-link-hover': c.accentText, '--nord-error': c.error,
    '--nord-success': c.success, '--nord-warning': c.warning,
  };
  const declarations = Object.entries(variables).map(([name, value]) => `  ${name}: ${hsl(value)} !important;`);
  declarations.push(...Object.entries(CDS_COLORS).map(([name, value]) => `  ${name}: ${value} !important;`));
  // These windows use hex values for older variables, not HSL components.
  declarations.push(`  --claude-foreground-color: ${c.text} !important;`,
    `  --claude-background-color: ${c.background} !important;`,
    `  --claude-text-500: ${c.textMuted} !important;`);
  return `${scope} {\n${declarations.join('\n')}\n}\n` +
    `${rootScope} { background-color: ${c.background} !important; }\n` +
    `${scope} :where(body,aside) { background-color: ${c.background} !important; }\n` +
    `${scope} :where([data-cds="Card"]) { background-color: ${c.surface} !important; }\n` +
    `${scope} [data-testid="chat-input"] { background-color: transparent !important; }\n` +
    `${scope} ::selection { background-color: hsl(var(--nord-selection-background)) !important; color: hsl(var(--nord-selection-text)) !important; }\n` +
    `${scope} :where(a):hover { color: hsl(var(--nord-link-hover)) !important; }\n` +
    // The ghost is a separate native overlay; accepted editor text keeps text-primary.
    `${scope} [data-prompt-suggestion-ghost] { color: ${c.promptSuggestion} !important; }\n` +
    // Outline paint does not change the composer's dimensions or move its controls.
    `${scope} :where([data-cds="ChatComposer"] > .rounded-composer,#chat-static-composer-box,#static-composer-box):focus-within { outline: 1px solid ${c.composerFocus} !important; outline-offset: -1px !important; }\n` +
    `${scope} :where(input,textarea,select,[role="textbox"]):focus-visible { border-color: hsl(var(--nord-focus)) !important; outline-color: hsl(var(--nord-focus)) !important; }\n`;
}

return { palette, nordThemeCss, nordComputedOverrides };
}
const themes={nord:createTheme(NORD),gruvbox:createTheme(GRUVBOX)};
function selected(name='nord') {
 if(!Object.hasOwn(themes,name))throw new TypeError('Unknown color theme');
 return themes[name];
}
module.exports = { NORD, GRUVBOX,
 palette:(name)=>selected(name).palette(),
 nordThemeCss:(options={})=>selected(options.theme).nordThemeCss(options),
 nordComputedOverrides:(...args)=>themes.nord.nordComputedOverrides(...args),
};
