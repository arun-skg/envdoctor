"""envdoctor — local-first environment-variable consistency checker (Python)."""

from .scanner import Finding, Origin, ScanResult, scan

__all__ = ["Finding", "Origin", "ScanResult", "scan"]
__version__ = "0.1.0"
