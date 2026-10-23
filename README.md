# MOKGOSI — Personal Safety & Response Network

Your call for help. A connected response.

Mokgosi connects an escort app to a responder console. The incident path does not wait on acoustic analysis. `DEMO_MODE` profiles are deterministic and are not YAMNet output. The default `console` notifier is DEMO ONLY and does not send SMS. Camera seeds are authorized demo entries and do not represent live camera integrations.

## Backend and database

1. Apply [`database/schema.sql`](database/schema.sql) in the Supabase SQL editor.
2. Create a private local environment file from `mokgosi-backend/.env.example`. Keep Supabase service-role credentials and the signing seed in the backend only.
3. Generate a persistent signing seed with `python scripts/gen_key.py` from `mokgosi-backend`, then put the printed value in its private `.env` as `ED25519_PRIVATE_KEY_SEED`. Do not commit the value.
4. Install and start the backend from `mokgosi-backend`:

   ```powershell
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install -r requirements.txt
   uvicorn main:app --env-file .env --reload
   ```

5. Configure a random `DEVICE_API_KEYS` value, then pass the same device key to the app as `MOKGOSI_DEVICE_API_KEY`. Set a trusted contact only after it has been provided and verified by the user, as `MOKGOSI_TRUSTED_CONTACT_PHONE`. The responder API verifies Supabase Auth bearer tokens. Keep `DEMO_MODE=false` outside the local demo.

## Dashboard

From `mokgosi-dashboard`, create a local `.env` from `.env.example`, set the Supabase project URL and anon key, then run `npm install` and `npm run dev`. Database RLS restricts anonymous access. Responder sign-in is a later phase; the current dashboard does not yet have a usable authenticated session flow.

## Flutter Android app

The Android project scaffold is included. If recreating it from a clean checkout, run this in `mokgosi-mobile`:

```powershell
flutter create --platforms=android --project-name mokgosi_mobile --no-pub .
```

Then restore the extra permissions and activity attributes in `android/app/src/main/AndroidManifest.xml` (the normal app scaffold does not include these). Install dependencies with `flutter pub get` and run:

```powershell
flutter run --dart-define=MOKGOSI_API_URL=http://10.0.2.2:8000 --dart-define=MOKGOSI_DEVICE_API_KEY=<device-key> --dart-define=MOKGOSI_TRUSTED_CONTACT_PHONE=<verified-E164-contact>
```

`10.0.2.2` reaches the host from the Android emulator. On a physical phone, replace it with the computer’s LAN IP address and ensure both devices can reach the backend. Provide a contact only after the user has set up and verified it; no contact number is bundled in the source.

## Notifier options

`NOTIFIER_PROVIDER=console` logs a DEMO ONLY notification and does not deliver it. `webhook` posts to `TRUSTED_NOTIFIER_WEBHOOK_URL`. `twilio` requires Twilio credentials and an approved sender. Twilio documents international SMS support for Botswana, but two-way SMS and domestic long codes are not supported; actual delivery still requires account, sender, carrier, and consent verification. See [Twilio Botswana SMS guidelines](https://www.twilio.com/en-us/guidelines/bw/sms). No live SMS delivery has been tested.

## Verification

From `mokgosi-backend`, run `python -m pytest -q`. The tests use a fake Supabase client and do not deploy SQL or send external notifications. Run `flutter analyze`, `flutter test`, `flutter run` from `mokgosi-mobile`, and `npm run build` from `mokgosi-dashboard` for the local checks.
