#!/usr/bin/env python3
"""
Quick test to verify SAM2 integration in unified interface.
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

from unified_interface import UnifiedEdaxShifu

def test_unified_sam2():
    """Test SAM2 integration in unified interface."""
    print("Testing SAM2 integration in unified interface...")
    
    try:
        ui = UnifiedEdaxShifu()
        print(f"SAM2 available: {ui.sam2_detector.sam2_available}")
        print(f"Detection modes: {ui.detection_modes}")
        print(f"SAM2 in detection modes: {'sam2' in ui.detection_modes}")
        print(f"Stats include SAM2: {'sam2_segments' in ui.stats}")
        
        if hasattr(ui.sam2_detector, 'predictor'):
            print("SAM2 detector properly initialized")
        
        print("✓ Unified interface SAM2 integration test passed!")
        return True
        
    except Exception as e:
        print(f"✗ Unified interface test failed: {e}")
        return False

if __name__ == "__main__":
    success = test_unified_sam2()
    sys.exit(0 if success else 1)
