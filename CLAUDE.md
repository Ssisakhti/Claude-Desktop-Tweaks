# Claude Desktop Tweaks

Use clear, concise English for repository content. Use the user's requested language in direct conversation.

- Use the standalone installer and automatic unpacked extension for user setup. Keep console integration code separate from the default installation.
- Do not change Claude's files, signature, ASAR archive, or security settings.
- Do not quit an open app automatically.
- Preserve document text, table column order, and control layout.
- Do not add app-patching or main-process debugger routes or dependencies.
- Do not commit private content, personal paths, credentials, or tokens.
- Preserve code license notices and the Estedad and Nord licenses.
- Run npm test, npm run check:fonts, and both Lua suites.
- Report live app checks separately from tests that use synthetic fixtures.
- Before replacing a running instance, confirm that it has stopped and completed cleanup.
