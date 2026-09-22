#!/bin/sh
#
# Katman sınırı kontrolü: Engine/ ve Parsing/ katmanları SwiftUI/UIKit import
# ETMEZ (motor UI'dan bağımsız kalmalı). Pre-commit hook'a bağlanır.
#
set -e

ROOT="$(git rev-parse --show-toplevel)"
HITS=$(grep -rlE 'import SwiftUI|import UIKit' \
    "$ROOT/InterestCalculator/Engine" \
    "$ROOT/InterestCalculator/Parsing" 2>/dev/null || true)

if [ -n "$HITS" ]; then
    echo "❌ Katman sınırı ihlali — Engine/ veya Parsing/ içinde SwiftUI/UIKit importu:"
    echo "$HITS"
    echo "   Motor katmanı yalnız Foundation import etmelidir."
    exit 1
fi

exit 0
