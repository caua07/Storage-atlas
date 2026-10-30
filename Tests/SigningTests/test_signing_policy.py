import importlib.util
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('signing', Path(__file__).resolve().parents[2] / 'scripts/app-signing.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningPolicyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name)
        self.config_patch = patch.object(signing, 'CONFIG', self.config)
        self.config_patch.start()
        self.addCleanup(self.config_patch.stop)

    def test_no_certificate_never_falls_back_to_adhoc(self):
        for mode in ['development', 'distribution']:
            with self.assertRaisesRegex(RuntimeError, 'No ad-hoc fallback'):
                signing.load_profile(mode)

    def test_certificate_kind_is_enforced(self):
        fingerprint = 'A' * 40
        signing.write_profile('distribution', {'identity': fingerprint})
        with patch.object(signing, 'identities', return_value={fingerprint: 'Apple Development: Fixture'}):
            with self.assertRaisesRegex(RuntimeError, 'wrong certificate type'):
                signing.load_profile('distribution')

    def test_missing_pinned_certificate_never_selects_another(self):
        signing.write_profile('development', {'identity': 'A' * 40})
        with patch.object(signing, 'identities', return_value={'B' * 40: 'Apple Development: Other'}):
            with self.assertRaisesRegex(RuntimeError, 'unavailable'):
                signing.load_profile('development')

    def test_ci_adhoc_requires_explicit_ci_environment(self):
        with patch.dict(os.environ, {'CI': 'false'}):
            with self.assertRaisesRegex(RuntimeError, 'restricted'):
                signing.load_profile('ci')
        with patch.dict(os.environ, {'CI': 'true'}):
            self.assertIsNone(signing.load_profile('ci'))

    def test_requirement_reads_certificates_and_commented_adhoc(self):
        for prefix in ['', '# ']:
            result = SimpleNamespace(stdout=prefix + 'designated => cdhash H"fixture"\n', stderr='Executable=/fixture\n')
            with patch.object(signing, 'run', return_value=result):
                self.assertEqual(signing.requirement(Path('/fixture')), 'cdhash H"fixture"')

    def test_certificate_rotation_preserves_original_requirement(self):
        original = {'identity': 'A' * 40, 'requirement': 'original-certificate-requirement', 'team': 'ORIGINAL'}
        signing.write_profile('development', original)
        with patch.object(signing, 'identities', return_value={'B' * 40: 'Apple Development: Fixture'}):
            with patch('sys.argv', ['app-signing.py', 'configure', 'development', 'B' * 40]):
                signing.main()
        saved = json.loads((self.config / 'development.json').read_text())
        self.assertEqual(saved['identity'], 'B' * 40)
        self.assertEqual(saved['requirement'], original['requirement'])
        self.assertEqual(saved['team'], original['team'])


if __name__ == '__main__':
    unittest.main()
