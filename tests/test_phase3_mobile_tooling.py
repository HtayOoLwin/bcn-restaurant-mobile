from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / 'mobile' / 'bcn_restaurant_mobile'


def test_mobile_sdk_matches_current_riverpod_requirement():
    pubspec = (MOBILE / 'pubspec.yaml').read_text(encoding='utf-8')
    assert 'sdk: ">=3.12.0 <4.0.0"' in pubspec


def test_android_setup_script_generates_android_and_runs_checks():
    script = (MOBILE / 'scripts' / 'setup_android.ps1').read_text(encoding='utf-8')
    assert 'flutter create .' in script
    assert '--platforms android' in script
    assert 'flutter pub get' in script
    assert 'flutter analyze' in script
    assert 'flutter test' in script


def test_android_run_script_passes_base_url_as_dart_define():
    script = (MOBILE / 'scripts' / 'run_android.ps1').read_text(encoding='utf-8')
    assert '--dart-define=BASE_URL=$BaseUrl' in script
    assert 'flutter run' in script


def test_readonly_smoke_script_never_calls_mutating_restaurant_methods():
    script = (MOBILE / 'scripts' / 'smoke_readonly.ps1').read_text(encoding='utf-8')
    assert 'bcn_mobile_bootstrap' in script
    assert 'bcn_mobile_tables' in script
    assert 'bcn_mobile_menu' in script
    assert 'bcn_waiter_order_progress' in script
    assert 'bcn_waiter_orders' in script
    assert 'bcn_kitchen_orders' not in script
    assert 'create_order' not in script
    assert 'update_item_status' not in script
    assert 'item_action' not in script
    assert 'serve_whole_order' not in script


def test_site_preflight_checks_bootstrap_read_only_without_kitchen_monitor():
    script = (MOBILE / 'scripts' / 'site_preflight.ps1').read_text(encoding='utf-8')
    assert 'bcn_mobile_bootstrap' in script
    assert 'Invoke-RestMethod' in script
    assert 'Method     = "Get"' in script
    assert 'permissions.kitchen' not in script
    assert 'bcn_kitchen_orders' not in script


def test_powershell_scripts_do_not_use_bash_line_continuations():
    for name in ('site_preflight.ps1', 'smoke_readonly.ps1'):
        lines = (MOBILE / 'scripts' / name).read_text(encoding='utf-8').splitlines()
        assert not any(line.rstrip().endswith('\\') for line in lines), name


def test_android_setup_manifest_patch_uses_real_newline_not_literal_backticks():
    script = (MOBILE / 'scripts' / 'setup_android.ps1').read_text(encoding='utf-8')
    assert "'<manifest$1>`r`n" not in script
    assert '[Environment]::NewLine' in script
