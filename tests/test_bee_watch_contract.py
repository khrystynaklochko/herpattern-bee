from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "HerPatternWatch"


class BeeWatchContract(unittest.TestCase):
    def test_watch_connects_directly_and_keeps_token_in_watch_keychain(self):
        client = (APP / "BeeWatchAPI.swift").read_text()
        store = (APP / "WatchSecureStore.swift").read_text()
        self.assertIn("api.developer.bee.amazon.dev", client)
        self.assertIn('"/v1/me"', client)
        self.assertIn("Bearer \" + token", client)
        self.assertIn("bee-developer-token", client)
        self.assertIn("kSecAttrAccessibleWhenUnlockedThisDeviceOnly", store)

    def test_selected_task_import_and_confirmed_plan_writeback(self):
        model = (APP / "WatchModel.swift").read_text()
        view = (APP / "HerPatternWatchApp.swift").read_text()
        client = (APP / "BeeWatchAPI.swift").read_text()
        self.assertIn('"/bee", method: "POST"', model)
        self.assertIn('"consent": true', model)
        self.assertIn("Review import to HerPattern", view)
        self.assertIn("Confirm import", view)
        self.assertIn('"/v1/todos", method: "POST"', client)
        self.assertIn("Review plan", view)
        self.assertIn("Confirm and send", view)
        self.assertIn("Disconnect Bee", view)
        self.assertIn('"/v1/conversations"', client)
        self.assertIn('"/v1/conversations/" + conversationID', client)
        self.assertIn('"action": "save_note"', model)
        self.assertIn('"confirm": false', model)
        self.assertIn('"confirm": true', model)
        self.assertIn("This was my statement", view)
        self.assertIn("Confirm and add to daily log", view)


if __name__ == "__main__":
    unittest.main()
