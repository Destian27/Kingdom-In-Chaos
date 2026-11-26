# Setup Google Auth — Kingdom In Chaos DTP

The Android client uses Supabase Auth Google OAuth with Authorization Code + PKCE.

## 1. Enable Google in Supabase

Open the Supabase project:

`https://supabase.com/dashboard/project/gunzwimrxspbmiducphg/auth/providers`

Open **Google**, enable the provider, and enter the Google **Web OAuth Client ID** and **Client Secret**.

## 2. Configure Google Cloud

Create an OAuth Client ID with application type **Web application**.

Add this Supabase callback as an Authorized redirect URI:

`https://gunzwimrxspbmiducphg.supabase.co/auth/v1/callback`

Copy the Web Client ID and Client Secret into the Supabase Google provider settings. Do not put the Client Secret in the Android source or APK.

## 3. Allow the Android deep link in Supabase

In Supabase **Authentication → URL Configuration → Redirect URLs**, add this exact URL:

`kingdominchaosdtp://auth`

The app manifest registers this URI and receives the one-time authorization code at the `GameAuthActivity`.

## 4. Build and test

Build the APK from this source using the included GitHub Actions workflow or:

`python3 build_dtp.py`

Then install the APK, open the game, press **LOGIN**, and finish Google sign-in in the external browser. The app should reopen using the deep link and exchange the code with Supabase. The Supabase access and refresh tokens are stored via Android Keystore encryption.

## Notes

- This does not use Firebase Authentication.
- The Google provider must be enabled in the Supabase Dashboard before the flow can succeed.
- Supabase Auth's Google provider uses the Google Web OAuth client. An Android OAuth client/SHA-1 setup is only needed if switching to Google's native Credential Manager flow.
- The login overlay is a Java-layer entry point. The original C++ avatar and legacy online UI are not directly hooked because their source UI code is not included in this project.
- The source package has passed repository tests, but an APK build and real-device OAuth test are still required.
