# Gson相关保护
-keep class com.google.gson.** {*;}
-keep class com.google.gson.reflect.** {*;}
-keepattributes Signature
-keepattributes *Annotation*

# 保持所有构造函数和方法不被混淆
-keepclassmembers class * {
    public void set*(***);
    public *** get*();
    public *** is*();
}

# Flutter插件保护
-keep class io.flutter.plugin.** {*;}

# 特定类忽略
-dontwarn com.google.gson.**

