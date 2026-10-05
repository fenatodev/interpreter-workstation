import { describe, expect, test } from 'bun:test';
import { redactSensitiveText, redactSensitiveValue } from './sensitiveText';

describe('redactSensitiveText', () => {
  test('redacts standard credential forms without dropping surrounding context', () => {
    expect(redactSensitiveText('Authorization: Bearer abcDEF123._-')).toContain('[REDACTED]');
    expect(redactSensitiveText('api_key=sk-example_12345678901234567890')).toContain('[REDACTED]');
  });

  test('redacts sk-style credentials separated by whitespace in window titles', () => {
    const synthetic = 'sk 0123456789abcdef0123456789abcdef.txt - Text Editor';
    const result = redactSensitiveText(synthetic);
    expect(result).toBe('[REDACTED].txt - Text Editor');
    expect(result).not.toContain('0123456789abcdef0123456789abcdef');
  });

  test('does not redact ordinary short prose', () => {
    expect(redactSensitiveText('notes about sk test in editor')).toBe('notes about sk test in editor');
  });
});

describe('redactSensitiveValue', () => {
  test('redacts nested structured MCP output', () => {
    const result = redactSensitiveValue({
      content: [{ type: 'text', text: 'title=sk 0123456789abcdef0123456789abcdef' }],
      structuredContent: {
        windows: [{ title: 'sk 0123456789abcdef0123456789abcdef.txt' }],
      },
    });

    expect(result.content[0].text).toBe('title=[REDACTED]');
    expect(result.structuredContent.windows[0].title).toBe('[REDACTED].txt');
  });

  test('preserves binary payload fields', () => {
    const binary = 'sk 0123456789abcdef0123456789abcdef';
    const result = redactSensitiveValue({
      content: [{ type: 'image', data: binary }],
      blob: binary,
    });
    expect(result.content[0].data).toBe(binary);
    expect(result.blob).toBe(binary);
  });
});
