#!/usr/bin/env python3
"""Exercise the built adapter against a fake bw; never access a real vault."""
import base64
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ADAPTER = Path(__file__).resolve().parents[1] / 'pwmplugin/binaries/iterm2-bitwarden-adapter'


class BitwardenAdapterTests(unittest.TestCase):
    def request(self, command, scenario):
        with tempfile.TemporaryDirectory() as directory:
            cli = Path(directory) / 'bw'
            cli.write_text('''#!/bin/sh
[ "$1" = "--nointeraction" ] && shift
case "$1" in
status) printf '%%s' '{"status":"locked"}' ;;
unlock) %s ;;
sync) exit 0 ;;
list) %s ;;
esac
''' % (
                "echo 'Decryption operation failed' >&2; exit 1" if scenario == 'wrong_password' else "printf 'fake-session'",
                "echo 'Vault is locked' >&2; exit 1" if scenario == 'locked' else
                "echo 'Network unavailable' >&2; exit 1" if scenario == 'network' else "printf '[]'"))
            cli.chmod(0o700)
            request = {
                'header': {'pathToExecutable': str(cli), 'mode': 'terminal'},
                'masterPassword': 'fake-password',
                'token': base64.b64encode(b'fake-session').decode(),
            }
            result = subprocess.run([str(ADAPTER), command], input=json.dumps(request),
                                    text=True, capture_output=True, timeout=10)
            return json.loads(result.stdout)

    def test_wrong_password_is_authentication_rejection(self):
        response = self.request('login', 'wrong_password')
        self.assertTrue(response['needsAuthentication'])
        self.assertEqual(response['error'], 'Incorrect master password.')

    def test_fresh_rejected_session_stops_login_loop(self):
        response = self.request('login', 'locked')
        self.assertIn('rejected its own session', response['error'])
        self.assertFalse(response.get('needsAuthentication', False))

    def test_expired_session_is_retryable(self):
        response = self.request('list-accounts', 'locked')
        self.assertTrue(response['needsAuthentication'])
        self.assertIn('Vault is locked', response['error'])

    def test_network_error_keeps_its_explanation(self):
        response = self.request('list-accounts', 'network')
        self.assertFalse(response.get('needsAuthentication', False))
        self.assertIn('Network unavailable', response['error'])


if __name__ == '__main__':
    unittest.main()
