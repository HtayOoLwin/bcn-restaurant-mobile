# Installation and First Run

## A. Repository location on Windows

Use the repository already cloned at:

```text
C:\Users\htayoolwin\bcn-restaurant-mobile
```

The Frappe app metadata is now at the repository root (`pyproject.toml`) and the Flutter app is under `mobile\bcn_restaurant_mobile`.

## B. Push this code to GitHub

From PowerShell:

```powershell
cd C:\Users\htayoolwin\bcn-restaurant-mobile
git status
git add .
git commit -m "feat: add BCN Restaurant mobile phase 1"
git push origin main
```

If you work on a feature branch first, push that branch and merge it after testing.

## C. Install backend on a local/WSL Frappe v16 bench

From the bench directory:

```bash
bench get-app /mnt/c/Users/htayoolwin/bcn-restaurant-mobile
bench --site <your-site> install-app bcn_restaurant
bench --site <your-site> migrate
bench --site <your-site> list-apps
```

This Phase 1 app intentionally expects the existing BCN Restaurant customization to already contain:
- Kitchen Counter DocType
- Item.custom_kitchen_counter
- Sales Order preparation summary/count fields
- Sales Order Item kitchen counter/status/note fields

The installer checks these prerequisites and fails with a readable message if they are missing.

After installation, open **Restaurant Settings** and verify:
- Company = BCN Restaurant
- POS Profile = BCN Restaurant POS
- Selling Price List = Restaurant Menu Price
- Currency = MMK
- Dine In Customer Group = Dine In
- Takeaway Customer Group = Takeaway

## D. Frappe Cloud

Custom GitHub apps require a **Private Bench Group**. In Frappe Cloud:

1. Open the Private Bench Group.
2. Open **Apps** → **Add App** → add the GitHub repository.
3. Select/deploy an update so the bench pulls the app.
4. Open the Site → **Apps** → **Install App** → install `bcn_restaurant`.
5. Run/deploy the bench update/migration through the Frappe Cloud UI.

The repository root contains `pyproject.toml` with Frappe/ERPNext v16 compatibility metadata specifically so Frappe Cloud can validate the app.

If the current site is on a public/shared bench, it cannot accept this custom GitHub app directly; move/use a Private Bench Group first.

## E. Existing Server Script migration note

The current site already has a Server Script named similar to:

```text
BCN Restaurant - Sales Order Kitchen Routing
```

The custom app now owns that routing in `bcn_restaurant/events/sales_order.py`. On a staging/test deployment:

1. Install the app while the existing script is still present.
2. Place a test order and verify counter/warehouse/status.
3. Disable the old Sales Order kitchen-routing Server Script.
4. Place another test order and verify again.

Do **not** disable the current cashier, auto Sales Invoice or Delivery Note scripts yet; those are replaced in later phases.

## F. Generate Flutter Android platform files on Windows

From PowerShell:

```powershell
cd C:\Users\htayoolwin\bcn-restaurant-mobile\mobile\bcn_restaurant_mobile
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap_flutter.ps1
```

The script runs:
- `flutter create` for Android platform files
- `flutter pub get`
- `flutter analyze`
- `flutter test`

For iOS, open the same repository on macOS and run:

```bash
cd mobile/bcn_restaurant_mobile
flutter create . --project-name bcn_restaurant_mobile --org com.bcn.restaurant --platforms ios
flutter pub get
```

## G. Run the Flutter app against the demo site

Windows / Android:

```powershell
flutter run --dart-define=BASE_URL=https://bcndemo-restaurant.nvi.frappe.cloud
```

Release APK later:

```powershell
flutter build apk --release --dart-define=BASE_URL=https://bcndemo-restaurant.nvi.frappe.cloud
```

## H. Phase 1 test checklist

1. Login as `waiter@bcnrestaurant.com`.
2. Confirm Dine In shows Table 01–Table 10.
3. Confirm Takeaway shows Takeaway 01–Takeaway 10.
4. Select a table.
5. Confirm Food Menu/Beverages and current MMK prices load.
6. Add multiple menu items.
7. Add a kitchen note to one line.
8. Place Order.
9. Confirm a submitted Sales Order is created in ERPNext.
10. Confirm Sales Order Item kitchen counter, warehouse and preparation status = New.
11. Confirm Restaurant Table Session is created/reused.
12. Simulate/retry the same request and confirm no duplicate Sales Order is created for the same `client_order_id`.
