# Metis Video Capabilities

Metis has two separate video paths.

## Video Understanding

Video understanding is for inbound IM media. Telegram video and video-note attachments are downloaded by the Telegram channel, attached to the turn as mediaContext, and then exposed through `telegram_video_describe`.

If no video understanding provider or companion analysis file is configured, the tool returns `videoUnderstandingStatus=not_configured` instead of guessing.

Configure shared video understanding under `gateway.media.video`; override Telegram-specific behavior under `gateway.telegram.video`.

Qwen/OpenAI-compatible video understanding can use DashScope compatible mode:

```json
{
  "gateway": {
    "media": {
      "video": {
        "enabled": true,
        "provider": "qwen-video-understanding",
        "maxBytes": 20971520,
        "maxBase64Bytes": 73400320,
        "timeoutMs": 120000,
        "providers": {
          "qwen-video-understanding": {
            "kind": "qwen-vl-video",
            "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "model": "qwen3-vl-plus",
            "apiKey": "${DASHSCOPE_API_KEY}"
          }
        }
      }
    }
  }
}
```

The provider sends an OpenAI-compatible `/chat/completions` request with a `video_url` data URL for media-understanding models that accept video input.

## Video Generation

Video generation is for user requests where Metis should create a new video. The agent calls `gateway_video_generate`, which uses the configured Gateway video generation runtime and returns generated video metadata. When the call happens inside an IM runtime context and delivery is enabled, Metis sends the first generated video through the existing `channels.send` path as a native video payload.

The tool marks the runtime context as visibly delivered after successful media delivery so the model can reply with `<silent_reply>` and avoid sending raw JSON/text back to the user.

Configure shared generation under `gateway.media.videoGeneration`; override Telegram-specific behavior under `gateway.telegram.videoGeneration`.

```json
{
  "gateway": {
    "media": {
      "videoGeneration": {
        "enabled": true,
        "provider": "qwen-video-generation",
        "outputRoot": "~/.metis/gateway-video-generation",
        "allowedOutputRoots": ["~/.metis/gateway-video-generation"],
        "providers": {
          "qwen-video-generation": {
            "kind": "dashscope-qwen-video-generation",
            "model": "wanx2.1-t2v-turbo",
            "apiKey": "${DASHSCOPE_API_KEY}"
          }
        }
      }
    },
    "telegram": {
      "actions": {
        "video": true
      }
    }
  }
}
```

`doctor` reports video generation `enabled`, `configured`, `provider`, `model`, and `outputRoot` without expanding provider secret fields.

## Image Generation

Image generation is for user requests where Metis should create a new image. The agent calls `gateway_image_generate`, which uses the configured Gateway image generation runtime and returns generated image metadata. When the call happens inside an IM runtime context and delivery is enabled, Metis sends the first generated image through the existing `channels.send` path as a native photo payload.

Configure shared generation under `gateway.media.imageGeneration`; override Telegram-specific behavior under `gateway.telegram.imageGeneration`. The OpenAI-compatible provider uses `/images/generations`, stores returned base64 or downloaded URL images under a managed output root, then sends the saved local path as a photo payload.

```json
{
  "gateway": {
    "media": {
      "imageGeneration": {
        "enabled": true,
        "provider": "openai-image",
        "outputRoot": "~/.metis/gateway-image-generation",
        "allowedOutputRoots": ["~/.metis/gateway-image-generation"],
        "providers": {
          "openai-image": {
            "kind": "openai-images",
            "baseUrl": "https://api.openai.com/v1",
            "model": "gpt-image-1",
            "apiKey": "${OPENAI_API_KEY}"
          }
        }
      }
    },
    "telegram": {
      "actions": {
        "photo": true
      }
    }
  }
}
```

DashScope Qwen Image uses DashScope's native multimodal generation endpoint, not OpenAI `/images/generations`. Configure it with `kind: "dashscope-qwen-image-generation"`:

```json
{
  "gateway": {
    "media": {
      "imageGeneration": {
        "enabled": true,
        "provider": "dashscope-qwen-image",
        "outputRoot": "~/.metis/gateway-image-generation",
        "allowedOutputRoots": ["~/.metis/gateway-image-generation"],
        "providers": {
          "dashscope-qwen-image": {
            "kind": "dashscope-qwen-image-generation",
            "baseUrl": "https://dashscope.aliyuncs.com/api/v1",
            "model": "qwen-image-2.0-pro",
            "apiKey": "${DASHSCOPE_API_KEY}"
          }
        }
      }
    },
    "telegram": {
      "actions": {
        "photo": true
      }
    }
  }
}
```

Do not configure DashScope Qwen Image as `kind: "openai-images"` with `baseUrl: "https://dashscope.aliyuncs.com/api/v1"`; that makes Metis call `/api/v1/images/generations`, which DashScope returns as 404.

`doctor` reports image generation `enabled`, `configured`, `provider`, `model`, `outputRoot`, and Telegram `photoActionEnabled` without expanding provider secret fields. Tests for this runtime use fake runners only; they do not call real image providers or Telegram.
