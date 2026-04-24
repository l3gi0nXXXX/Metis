package metis.gateway.channels

/**
 * 渠道目录锚点文件。
 *
 * 作用：
 * - 确保 `src/gateway/channels/xx` 子目录参与源码扫描；
 * - 避免仅有二级子目录（如 feishu）时被编译器跳过。
 */
public const CHANNELS_MODULE_ANCHOR: String = "channels-module-anchor"
