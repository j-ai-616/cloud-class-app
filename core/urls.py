from django.urls import path

from . import views


urlpatterns = [
    path("", views.index, name="index"),
    path("health/", views.health, name="health"),
    path("api/info/", views.info, name="info"),
]
