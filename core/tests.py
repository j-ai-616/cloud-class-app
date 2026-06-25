from django.test import TestCase
from django.urls import reverse


class CoreViewTests(TestCase):
    def test_index_page(self):
        response = self.client.get(reverse("index"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Cloud Class CI/CD")
        self.assertContains(response, "테스트를 통과한 Django 애플리케이션")

    def test_health_endpoint(self):
        response = self.client.get(reverse("health"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {"status": "ok", "service": "cloud-class-app"},
        )

    def test_info_endpoint(self):
        response = self.client.get(reverse("info"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["service"], "cloud-class-app")
        self.assertIn("environment", response.json())
        self.assertIn("version", response.json())
