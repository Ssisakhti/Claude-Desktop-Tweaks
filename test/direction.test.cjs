'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { estimateDirection, stableDirection, DEFAULTS } = require('../lib/persian/direction.cjs');

const direction = text => estimateDirection(text).direction;

test('An API prefix does not determine Persian paragraph direction', () => {
  const result = estimateDirection('API برای این پروژه باید سه تغییر را ثبت کند.');
  assert.equal(result.direction, 'rtl');
  assert.equal(result.ltrWords, 1);
  assert.equal(result.rtlWords, 9);
});

test('One Persian word does not change an English sentence direction', () => {
  assert.equal(direction('The Persian word «سلام» means hello.'), 'ltr');
});

test('The reference threshold is exact: 40 percent is LTR and higher is RTL', () => {
  assert.equal(direction('یک دو one two three'), 'ltr');
  assert.equal(direction('یک دو سه one two'), 'rtl');
});

test('Zero-width non-joiners do not count a Persian word twice', () => {
  assert.deepEqual(estimateDirection('می‌توانیم پروژه‌ها را بررسی‌کنیم'), {
    direction: 'rtl', rtlWords: 4, ltrWords: 0, ratio: 1,
  });
});

test('Persian, Arabic, and Latin digits, emoji, marks, and direction controls are neutral', () => {
  assert.deepEqual(estimateDirection('۱۲۳ ١٢٣ 123 🧊 😀 َ ِ \u061c \u200f'), {
    direction: 'neutral', rtlWords: 0, ltrWords: 0, ratio: 0,
  });
});

test('Marks and punctuation before a letter do not produce incorrect votes', () => {
  assert.equal(direction('َسلام'), 'rtl');
  assert.equal(direction('123API'), 'ltr');
  assert.equal(direction('🧊 گزارش'), 'rtl');
});

test('Hebrew letters also count as RTL', () => {
  assert.equal(direction('שלום עולם'), 'rtl');
});

test('Non-Latin left-to-right letters also vote', () => {
  assert.equal(direction('Français Ελληνικά 中文'), 'ltr');
});

test('URLs and www do not vote even with Persian paths', () => {
  const result = estimateDirection('بررسی https://example.com/گزارش www.example.com/test را انجام بده');
  assert.equal(result.direction, 'rtl');
  assert.equal(result.ltrWords, 0);
  assert.equal(result.rtlWords, 4);
});

test('Exclude email addresses from direction votes', () => {
  assert.equal(estimateDirection('گزارش را به test@example.com بفرست').ltrWords, 0);
  assert.equal(direction('test@example.com'), 'neutral');
});

test('Unix, Windows, relative paths, and filenames do not vote', () => {
  for (const value of ['/Users/demo/readme.md', '~/Desktop/گزارش.txt', '../src/index.js', 'src/index.js', 'C:\\Users\\Demo\\file.txt', '\\\\server\\share\\file.txt', 'README.md', 'README.md.', '.env']) {
    assert.equal(direction(value), 'neutral', value);
  }
});

test('Exclude inline code and unfinished inline code during typing', () => {
  assert.equal(estimateDirection('این `const value = true` را بررسی کن').ltrWords, 0);
  assert.equal(direction('گزارش `const value'), 'rtl');
  assert.equal(direction('`const value = true`'), 'neutral');
});

test('Complete and unfinished code fences do not distort paragraph direction', () => {
  const sample = 'این گزارش فارسی است\n```js\nconst words = "many English words here";\n```\nاین بخش ادامه دارد';
  assert.equal(estimateDirection(sample).ltrWords, 0);
  assert.equal(direction('```js\nconst words = true;'), 'neutral');
  assert.equal(direction('~~~python\nprint("hello")\n~~~'), 'neutral');
});

test('Markdown links vote only through readable labels', () => {
  const result = estimateDirection('[گزارش](https://example.com/report) را بررسی کن');
  assert.equal(result.direction, 'rtl');
  assert.equal(result.ltrWords, 0);
});

test('Empty or invalid input is explicitly neutral', () => {
  for (const input of ['', ' \n\t', null, undefined, 42]) assert.equal(direction(input), 'neutral');
});

test('The initial threshold is configurable and input remains unchanged', () => {
  const text = 'یک دو سه one two';
  assert.equal(estimateDirection(text, { rtlThreshold: .7 }).direction, 'ltr');
  assert.equal(text, 'یک دو سه one two');
  assert.equal(DEFAULTS.rtlThreshold, .4);
});

test('Stabilization uses the initial estimator for the first decision', () => {
  assert.equal(stableDirection('API این متن فارسی است', 'neutral'), 'rtl');
  assert.equal(stableDirection('The word سلام is Persian', undefined), 'ltr');
});

test('Minimum evidence prevents direction switches in short strings', () => {
  assert.equal(stableDirection('سلام', 'ltr'), 'ltr');
  assert.equal(stableDirection('hello world', 'rtl'), 'rtl');
});

test('The stabilization band prevents oscillation around the threshold', () => {
  assert.equal(stableDirection('یک دو سه one two three', 'ltr'), 'ltr');
  assert.equal(stableDirection('یک دو one two three', 'rtl'), 'rtl');
  assert.equal(stableDirection('یک دو سه one two', 'ltr'), 'rtl');
  assert.equal(stableDirection('یک one two three', 'rtl'), 'ltr');
});

test('Cleared or neutral paragraphs reset direction memory', () => {
  assert.equal(stableDirection('', 'rtl'), 'neutral');
  assert.equal(stableDirection('۱۲۳ 😀', 'rtl'), 'neutral');
  assert.equal(stableDirection('hello', 'neutral'), 'ltr');
});

test('Stabilization parameters are configurable', () => {
  assert.equal(stableDirection('سلام', 'ltr', { minSwitchWords: 1 }), 'rtl');
  assert.equal(stableDirection('یک دو سه one two', 'ltr', { switchToRtlRatio: .8 }), 'ltr');
});

test('Invalid settings throw clear errors instead of guessing direction', () => {
  for (const value of [-.1, 1.1, NaN, '0.4']) assert.throws(() => estimateDirection('سلام', { rtlThreshold: value }), RangeError);
  assert.throws(() => stableDirection('سلام', 'rtl', { minSwitchWords: 0 }), RangeError);
  assert.throws(() => stableDirection('سلام', 'rtl', { switchToLtrRatio: .8, switchToRtlRatio: .6 }), RangeError);
});


test('Process long words and unfinished paths without costly scanning', { timeout: 2500 }, () => {
  assert.equal(direction('a'.repeat(100000)), 'ltr');
  assert.equal(direction('a'.repeat(100000) + '/'), 'neutral');
  assert.equal(direction('سلام'.repeat(25000)), 'rtl');
});
