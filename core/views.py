import os

from django.http import JsonResponse
from django.shortcuts import render


def index(request):
    context = {
        "environment": os.environ.get("APP_ENV", "local"),
        "version": os.environ.get("APP_VERSION", "dev"),
    }
    return render(request, "core/index.html", context)


def health(request):
    return JsonResponse({"status": "ok", "service": "cloud-class-app"})


def info(request):
    return JsonResponse(
        {
            "service": "cloud-class-app",
            "environment": os.environ.get("APP_ENV", "local"),
            "version": os.environ.get("APP_VERSION", "dev"),
        }
    )
