# Phase 3: Android End-to-End Run

Phase 3 turns the existing Flutter source into an Android project, verifies the ERPNext/Frappe backend is installed, and provides a read-only API smoke test before any live restaurant transaction is created.

## 1. Backend deployment is required first

The GitHub repository can be pushed without changing the live site. The mobile APIs become available only after the `bcn_restaurant` Frappe app is added to the bench and installed on the target site.

Target site:

```text
https://bcndemo-restaurant.nvi.frappe.cloud
```

Required backend records after installation:

- `Restaurant Settings`
- `Restaurant Table Session`
- Sales Order custom field `custom_restaurant_session`
- Sales Order custom field `custom_client_order_id`

The app installation hook also checks the existing restaurant customizations before installation, including `Kitchen Counter` and the preparation fields already present on the BCN Restaurant site.

### Frappe Cloud private bench flow

1. Open the target **Bench Group**.
2. Open **Apps** and choose **Add App**.
3. Add the GitHub repository `HtayOoLwin/bcn-restaurant-mobile`.
4. Deploy/update the bench and select the BCN Restaurant site during the update.
5. After the deploy finishes, open the site's **Apps** tab.
6. Install `BCN Restaurant` / `bcn_restaurant` on the site.
7. Confirm that `Restaurant Settings` contains:
   - Company: `BCN Restaurant`
   - POS Profile: `BCN Restaurant POS`
   - Selling Price List: `Restaurant Menu Price`
   - Currency: `MMK`
   - Dine In Customer Group: `Dine In`
   - Takeaway Customer Group: `Takeaway`

The `after_install` hook initializes these defaults when the matching records exist.

## 2. Run the backend preflight from Windows

From the Flutter project folder:

```powershell
cd C:\Users\htayoolwin\bcn-restaurant-mobile\mobile\bcn_restaurant_mobile

$Password = Read-Host "ERPNext password" -AsSecureString
.\scripts\site_preflight.ps1 -User "Administrator" -Password $Password
```

This script logs in and performs read-only checks for the two custom DocTypes and the bootstrap API. It does not create or modify restaurant transactions.

Expected successful output includes:

```text
OK: Restaurant Settings exists
OK: Restaurant Table Session exists
OK: bcn_restaurant mobile API is installed
Company: BCN Restaurant
Price List: Restaurant Menu Price
```

## 3. Generate the Android project

```powershell
cd C:\Users\htayoolwin\bcn-restaurant-mobile\mobile\bcn_restaurant_mobile
.\scripts\setup_android.ps1
```

The setup script:

- verifies Flutter and Dart are in `PATH`
- requires Dart 3.12.0 or newer
- generates the `android/` platform folder when missing
- adds the Android `INTERNET` permission to the main manifest
- runs `flutter pub get`
- runs `flutter analyze`
- runs `flutter test`

## 4. Read-only live API smoke test

Use a restaurant user such as the waiter or a kitchen user:

```powershell
$Password = Read-Host "ERPNext password" -AsSecureString
.\scripts\smoke_readonly.ps1 -User "waiter@bcnrestaurant.com" -Password $Password
```

The script logs in and checks only GET endpoints:

- bootstrap
- waiter table list
- menu
- kitchen queue when the user has Kitchen permission

It deliberately does not call order creation or status mutation APIs.

## 5. Connect an Android device

```powershell
adb devices
flutter devices
```

The device should appear as `device`, not `unauthorized` or `offline`.

## 6. Run the app

Default BCN demo site:

```powershell
.\scripts\run_android.ps1
```

Specific device:

```powershell
.\scripts\run_android.ps1 -DeviceId "YOUR_DEVICE_ID"
```

Different ERPNext site:

```powershell
.\scripts\run_android.ps1 -BaseUrl "https://your-site.example.com"
```

The script passes the site URL to Flutter using:

```text
--dart-define=BASE_URL=<site-url>
```

No API key, secret, or password is compiled into the application.

## 7. Manual end-to-end restaurant smoke flow

Only run this after the read-only smoke test is clean.

### Waiter

1. Login as `waiter@bcnrestaurant.com`.
2. Open **Dine In**.
3. Select a free table.
4. Add one menu item.
5. Add a kitchen note if desired.
6. Place the order.
7. Confirm the Sales Order and Restaurant Table Session appear in ERPNext.

### Kitchen

1. Login as the kitchen user assigned to that item's Kitchen Counter.
2. Confirm only the permitted counter queue is visible.
3. Accept the item.
4. Start Preparation.
5. Mark Ready.

### Waiter finish

1. Login as the waiter again.
2. Open **Ready to Serve**.
3. Mark the item Served.
4. Confirm Order Progress reflects the Served state.

## 8. What Phase 3 intentionally does not do

- Cashier billing/payment is not included yet.
- Delivery Note auto-submission is not included yet.
- Full offline ordering is not included.
- The smoke script never creates a live order automatically.

Those operations belong to the next implementation phases because they create accounting and stock effects.
