"""An invalid parameter simulation must fail with the intended diagnostic."""
import subprocess
import sys

result = subprocess.run([sys.argv[1]], stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, text=True, timeout=15)
if result.returncode == 0 or "INVALID_PE_CONFIGURATION" not in result.stdout:
    print(result.stdout)
    raise SystemExit("FAIL: expected explicit invalid-configuration rejection")
print("PASS: PE8_MODE=0 RESULT_PIPELINED=1 rejected at simulation startup")
