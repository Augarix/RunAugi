def flutterRoot = rootProject.ext.flutterSdkPath
        apply from: "$flutterRoot/packages/flutter_tools/gradle/flutter.gradle"

android {
    namespace "cz.augarix.runaugi"
    compileSdkVersion 35
    ndkVersion flutter.ndkVersion

            defaultConfig {
                applicationId "cz.augarix.runaugi"
                minSdkVersion 28
                targetSdkVersion 35
                versionCode 1
                versionName "0.1.0"
                multiDexEnabled true
            }

    buildTypes {
        release {
            signingConfig signingConfigs.debug
                    minifyEnabled false
            shrinkResources false
        }
        debug {
            debuggable true
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
                targetCompatibility JavaVersion.VERSION_17
    }

    packagingOptions {
        resources {
            excludes += ['/META-INF/{AL2.0,LGPL2.1}']
        }
    }
}

flutter {
    source '../..'
}

dependencies {
    implementation "com.android.support:multidex:1.0.3"
}
