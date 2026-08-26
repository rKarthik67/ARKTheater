Since your Android SDK and Flutter live on your actual Windows machine (not the sandboxed VM this session's device-bridge reaches), you'll run these commands yourself in a terminal on your PC. Here's the full path from zero to a running app on your device.

## 1. Start the scraper backend

In PowerShell/terminal:

```powershell
cd "C:\Users\LEGION\Documents\Karthikeyan Important MSI transfered Files\Movie-and-tv-show-2\repo push git hub\ARKVideoScrapper"
npm install
npx playwright install chromium
copy .env.example .env
npm run dev
```

Leave this running — it's your API server. Confirm it's alive by opening `http://localhost:4040/api/health` in a browser. A real test like `http://localhost:4040/api/movie/27205` will take several seconds the first time (it's driving a real headless browser), then comes back instantly from cache on repeat calls.

## 2. Install Flutter (you only have the Android SDK so far)

Download the Flutter SDK zip for Windows from flutter.dev, extract it somewhere like `C:\src\flutter`, then add `C:\src\flutter\bin` to your PATH. Open a new terminal and run:

```powershell
flutter doctor
```

It should detect your existing Android SDK. If it flags unaccepted licenses: `flutter doctor --android-licenses` (accept them all).

## 3. Scaffold the native Android project

```powershell
cd "...\repo push git hub\ARKTheater"
flutter create . --platforms=android --org com.ark.theater
flutter pub get
```

This fills in the missing `android/` folder without touching any of the Dart code already there.

## 4. Point the app at your scraper (the part people usually trip on)

Android can't reach your PC's `localhost` the way a browser on the same machine can — `localhost` on the device means the device itself. Edit `ARKTheater\.env`:

- **Android emulator**: `SCRAPER_BASE_URL=http://10.0.2.2:4040` (Google's special alias for "the host machine")
- **Physical phone over USB**: plug it in, run `adb reverse tcp:4040 tcp:4040`, then keep `SCRAPER_BASE_URL=http://localhost:4040` — the reverse tunnel makes the device's localhost:4040 forward to your PC
- **Physical phone over WiFi**: find your PC's LAN IP (`ipconfig`, look for IPv4), use `SCRAPER_BASE_URL=http://<that-ip>:4040`, and make sure phone + PC are on the same network

Also, Android blocks plain HTTP by default since your scraper isn't HTTPS. After step 3 generates `android/app/src/main/AndroidManifest.xml`, add `android:usesCleartextTraffic="true"` to the `<application ...>` tag — otherwise every scraper call will silently fail from the device.

## 5. Run it

```powershell
flutter devices        # confirm your emulator/phone shows up
flutter run             # pick it, or: flutter run -d <device-id>
```

Home/Search should populate immediately from TMDB. Hitting Play on a title is the real test of the scraper connection — expect a several-second spinner ("Finding ad-free source...") on first play of a title while it scrapes live, then it plays natively.

If `flutter run` fails at the Gradle step, it's almost always an Android SDK/NDK version mismatch — paste me the error and I'll help sort it. Want me to also add a quick smoke-test script that hits the scraper's `/api/movie/:id` endpoint from PowerShell so you can confirm step 1 works before touching Flutter at all?