# NewPipeExtractor (Rhino, protobuf) relies on reflection and optional JDK classes
# that do not exist on Android. Keep everything and ignore the missing ones.
-ignorewarnings
-dontwarn java.beans.**
-dontwarn javax.script.**
-dontwarn org.mozilla.**
-dontshrink
-dontoptimize
-dontobfuscate
