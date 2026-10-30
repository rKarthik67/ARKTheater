# libtorrent4j resolves these generated Java callbacks by name from
# libtorrent4j.so. Keep all bridge classes and their members in release APKs.
-keep class org.libtorrent4j.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
