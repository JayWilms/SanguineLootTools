from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
(root / 'work').mkdir(exist_ok=True)
checks = [
    'check_history_filters.py',
    'check_history_sync.py',
    'check_native_distribution.py',
    'check_corpse_transport.py',
    'check_corpse_routes.py',
    'check_timer_scroll.py',
    'check_trade_timers.py',
    'check_raid_member_pickers.py',
    'check_raid_setup.py',
    'check_window_drag.py',
    'check_window_layers.py',
    'check_class_autopass.py',
    'check_voting_trade.py',
    'check_correction_dropdown.py',
    'check_handovers.py',
    'check_queue_completion.py',
    'check_pickups.py',
    'check_reason_dropdown.py',
    'check_quality_rules.py',
    'check_alpha36.py',
]
for name in checks:
    result = subprocess.run([sys.executable, str(root / 'qa' / name)], cwd=root, capture_output=True, text=True)
    if result.returncode:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)
    print('PASS: ' + name)
print(f'All {len(checks)} suites passed. These simulations do not replace native in-game testing.')
