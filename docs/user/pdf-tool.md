# PDF Tool

Metis exposes an agent tool named `pdf` for reading, summarizing, comparing, and extracting content from PDF documents. The tool accepts local file paths, `file://` URLs, and `http://` or `https://` URLs when the configured runtime allows remote loading.

The current landing phase registers the agent tool and diagnostics boundary. The PDF loader, extractor, and model runner are supplied by the PDF runtime worker in the runtime phase.

## Configuration

Add a dedicated PDF model when you want PDF analysis to use a model separate from the main chat model:

```json
{
  "agents": {
    "defaults": {
      "pdfModel": {
        "primary": "anthropic/claude-sonnet-4-5",
        "fallbacks": ["qwen/qwen-vl-max"]
      },
      "pdfMaxBytesMb": 10,
      "pdfMaxPages": 20
    }
  }
}
```

If `agents.defaults.pdfModel` is absent, Metis diagnostics fall back to `agents.defaults.imageModel` and then `agents.defaults.model` as candidate sources.

## Fallback Dependencies

Text extraction fallback is provided by the PDF runtime worker. When that worker is installed, its Node package should live under `tools/pdf_extract` and provide:

- `pdfjs-dist`
- `@napi-rs/canvas`

Install the fallback dependencies from the Metis repository root:

```bash
npm --prefix tools/pdf_extract install
```

Restart the Gateway after installing dependencies so the running process can use the extractor:

```bash
metis gateway restart
```

Run the diagnostic command to check whether those packages are loadable:

```bash
metis models pdf-status
```

The default output is human-readable. Use `--json` only for machine-readable diagnostics. A healthy fallback setup should show `pdfjs-dist` and `@napi-rs/canvas` as `loadable`.

These dependencies are required when the selected PDF model candidate is not a native PDF provider and Metis must first extract PDF text or render page images locally. Native PDF providers can read PDF bytes directly, but fallback models such as vision/text chat models need the local extractor path.

## CLI Usage

Ask the agent to use the PDF tool explicitly:

```bash
metis agent --message "请用 pdf tool 总结 /tmp/report.pdf"
```

For multiple PDFs:

```bash
metis agent --message "请用 pdf tool 对比 /tmp/q1.pdf 和 /tmp/q2.pdf 的风险变化"
```

## IM Usage

In Telegram, send a PDF to the bot, then ask:

```text
总结这份 PDF
```

The Telegram adapter should only stage and pass the document through the existing media runtime. PDF content analysis belongs to the shared PDF runtime, not the IM adapter.
