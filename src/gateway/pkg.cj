package metis.gateway

// /**
//  * 目录锚点文件（module anchor）。
//  *
//  * 作用：
//  * - 某些编译扫描策略下，若目录本身没有 .cj 文件，则其子目录可能不会被递归扫描；
//  * - 保留该文件可确保 `src/gateway/**` 下的新模块被稳定纳入编译单元。
//  *
//  * 注意：
//  * - 该文件不承载业务逻辑，仅用于编译可见性。
//  */
// public const GATEWAY_MODULE_ANCHOR: String = "gateway-module-anchor"
