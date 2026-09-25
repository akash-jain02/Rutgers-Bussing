"""Run the same Swift edge-case tests without XCTest (Command Line Tools fallback)."""
import pathlib
import re
import subprocess
import tempfile
root = pathlib.Path(__file__).resolve().parents[1]
tests = root/'Tests/DepartureCoreTests/DepartureTests.swift'
names = re.findall(r'func (test\w+)\(', tests.read_text())
with tempfile.TemporaryDirectory(prefix='rutgers-tests-') as folder:
    folder = pathlib.Path(folder)
    main = folder/'main.swift'
    main.write_text('let suite = DepartureTests()\n' + '\n'.join(f'suite.{name}()' for name in names) + f'\nprint("{len(names)} Swift timing tests passed")\n')
    subprocess.run(['swiftc', '-D', 'CORE_CLI_TESTS', str(root/'Sources/DepartureCore/Departure.swift'), str(tests), str(main), '-o', str(folder/'tests')], check=True)
    subprocess.run([str(folder/'tests')], check=True)
