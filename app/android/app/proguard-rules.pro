# ML Kit 文本识别按语言拆分依赖：本项目仅打包中文模型，
# 插件代码仍引用天城文/日文/韩文等可选识别器，R8 需忽略这些缺失类。
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }
