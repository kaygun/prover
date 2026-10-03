"""CLI integration tests using only Python's standard library."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "prover.lisp"


class CommandLineTests(unittest.TestCase):
    def run_cli(self, *arguments, cwd=None):
        return subprocess.run(
            ["sbcl", "--script", str(SCRIPT), *map(str, arguments)],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=15,
        )

    def test_examples(self):
        examples = sorted((ROOT / "examples").glob("*.nd"))
        self.assertEqual(len(examples), 10)
        for example in examples:
            with self.subTest(example=example.name):
                result = self.run_cli(example)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                self.assertTrue(result.stdout.strip())

    def test_usage(self):
        for arguments in [(), ("one", "two")]:
            with self.subTest(arguments=arguments):
                result = self.run_cli(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertIn("Usage:", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_missing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_cli(Path(directory) / "missing.nd")
            self.assertEqual(result.returncode, 1)
            self.assertIn("Error:", result.stderr)
            self.assertEqual(result.stdout, "")

    def test_input_errors(self):
        cases = {
            "missing separator": "P\nQ\n",
            "short separator": "P\n----\nP\n",
            "multiple separators": "P\n-----\nP\n-----\n",
            "missing conclusion": "P\n-----\n",
            "multiple conclusions": "P\n-----\nP\nQ\n",
            "bad formula": "P\n-----\nP ->\n",
        }
        with tempfile.TemporaryDirectory() as directory:
            problem = Path(directory) / "input.nd"
            for label, contents in cases.items():
                with self.subTest(case=label):
                    problem.write_text(contents)
                    result = self.run_cli(problem)
                    self.assertEqual(result.returncode, 1)
                    self.assertIn("Error:", result.stderr)
                    self.assertEqual(result.stdout, "")

    def test_unprovable(self):
        with tempfile.TemporaryDirectory() as directory:
            problem = Path(directory) / "invalid.nd"
            problem.write_text("P\n-----\nQ\n")
            result = self.run_cli(problem)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr, "No proof found.\n")
            self.assertEqual(result.stdout, "")

    def test_premise_goal_and_working_directory(self):
        with tempfile.TemporaryDirectory(prefix="nd prover ") as directory:
            problem = Path(directory) / "with spaces.nd"
            problem.write_bytes(b"\r\n P\r\nQ\r\n  ----- \r\n\tP\r\n\r\n")
            result = self.run_cli(problem.name, cwd=directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertRegex(result.stdout.splitlines()[-1], r"3\. P\s+R\s+1$")

    def test_no_premises(self):
        with tempfile.TemporaryDirectory() as directory:
            problem = Path(directory) / "identity.nd"
            problem.write_text("-----\nP -> P\n")
            result = self.run_cli(problem)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("P → P", result.stdout.splitlines()[-1])

    def test_library_load_does_not_exit(self):
        result = subprocess.run(
            [
                "sbcl", "--noinform", "--non-interactive",
                "--load", str(ROOT / "nd-prover.lisp"),
                "--eval", '(format t "Library loaded.~%")',
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "Library loaded.\n")
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
