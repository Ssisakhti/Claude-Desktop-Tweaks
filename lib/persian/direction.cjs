'use strict';

/*
 * Independent paragraph base-direction estimation, without character reordering.
 * Reference for word counting and the initial threshold:
 * https://github.com/google/closure-library/blob/master/closure/goog/i18n/bidi.js
 * estimateDirection: the RTL word ratio must exceed 0.4.
 * This is not copied Google code and does not replace Unicode BiDi.
 * The browser uses the standard algorithm for ordering within each paragraph:
 * https://www.unicode.org/reports/tr9/
 */
const LETTER = /\p{Letter}/u;
const RTL_LETTER = /(?:\p{Script_Extensions=Arabic}|\p{Script_Extensions=Hebrew})/u;
const DEFAULTS = Object.freeze({
  rtlThreshold: 0.4,
  switchToRtlRatio: 0.6,
  switchToLtrRatio: 0.3,
  minSwitchWords: 3,
});

function ratioOption(options, key) {
  const value = options[key] ?? DEFAULTS[key];
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) {
    throw new RangeError(`${key} must be a finite number between 0 and 1`);
  }
  return value;
}

// Clean only a temporary counting copy. Keep the input text unchanged.
function visibleProse(text) {
  let fence = null;
  const lines = text.split(/\r?\n/).map(line => {
    const marker = line.match(/^\s{0,3}(`{3,}|~{3,})/);
    if (fence) {
      if (marker && marker[1][0] === fence.character && marker[1].length >= fence.length) fence = null;
      return '';
    }
    if (marker) {
      fence = { character: marker[1][0], length: marker[1].length };
      return '';
    }
    return line;
  });
  return lines.join('\n')
    // Treat an unfinished code fence as code through the end of the paragraph.
    .replace(/(`+)[^`]*(?:`+|$)/g, ' ')
    .replace(/(?:[a-z][a-z0-9+.-]{0,30}:\/\/|www\.)[^\s<>()]+/giu, ' ');
}

function isFilePath(token) {
  const value = token.replace(/^[('"\[{]+|[)'"\]},;:!?،؛؟.]+$/gu, '');
  // Exclude path separators from voting. The caller also excludes known code.
  if (value.includes('/') || value.includes('\\')) return true;
  // A standalone filename or domain does not determine sentence direction.
  return /^\.[\p{Letter}\p{Number}_-]+$/u.test(value) || /^[^\s@/\\]+\.[a-z0-9]{1,12}$/iu.test(value);
}

function estimateDirection(text, options = {}) {
  const threshold = ratioOption(options, 'rtlThreshold');
  const input = typeof text === 'string' ? text : '';
  let rtlWords = 0;
  let ltrWords = 0;
  for (const token of visibleProse(input).split(/\s+/u)) {
    if (!token || isFilePath(token) || (token.includes('@') && /^[^@]+@[^@]+\.[^@]+$/u.test(token))) continue;
    // The first letter of each word votes. Digits, marks, and emoji do not vote.
    // A zero-width non-joiner does not split a word.
    for (const character of token) {
      if (!LETTER.test(character)) continue;
      if (RTL_LETTER.test(character)) rtlWords++;
      else ltrWords++;
      break;
    }
  }
  const total = rtlWords + ltrWords;
  const ratio = total ? rtlWords / total : 0;
  return {
    direction: total === 0 ? 'neutral' : ratio > threshold ? 'rtl' : 'ltr',
    rtlWords,
    ltrWords,
    ratio,
  };
}

/*
 * Return a direction string and prevent direction jumps while typing or streaming.
 * Defaults: at least 3 words; switch LTR to RTL above 0.6 and RTL to LTR below 0.3.
 * These stabilization thresholds are project choices, not part of the Google method.
 * Use stateless estimateDirection for finalized text when appropriate.
 * Empty or fully neutral text resets the remembered direction to neutral.
 */
function stableDirection(text, previous = 'neutral', options = {}) {
  const high = ratioOption(options, 'switchToRtlRatio');
  const low = ratioOption(options, 'switchToLtrRatio');
  const minimum = options.minSwitchWords ?? DEFAULTS.minSwitchWords;
  if (!Number.isInteger(minimum) || minimum < 1) throw new RangeError('minSwitchWords must be a positive integer');
  if (low >= high) throw new RangeError('switchToLtrRatio must be below switchToRtlRatio');
  const estimate = estimateDirection(text, options);
  if (estimate.direction === 'neutral') return 'neutral';
  if (previous !== 'rtl' && previous !== 'ltr') return estimate.direction;
  if (estimate.direction === previous) return previous;
  if (estimate.rtlWords + estimate.ltrWords < minimum) return previous;
  if (previous === 'ltr' && estimate.ratio >= high) return 'rtl';
  if (previous === 'rtl' && estimate.ratio <= low) return 'ltr';
  return previous;
}

module.exports = { estimateDirection, stableDirection, DEFAULTS };
