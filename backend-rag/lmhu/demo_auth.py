import ipaddress

from django.conf import settings
from django.contrib.auth import authenticate
from django.http import Http404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken


def _is_loopback_request(request) -> bool:
    try:
        host = request.get_host().split(":", maxsplit=1)[0].lower()
        remote_address = ipaddress.ip_address(
            request.META.get("REMOTE_ADDR", "")
        )
    except (ValueError, TypeError):
        return False

    return host in {"localhost", "127.0.0.1"} and remote_address.is_loopback


def _invalid_credentials_response() -> Response:
    response = Response(
        {"detail": "Invalid local demo credentials."},
        status=status.HTTP_401_UNAUTHORIZED,
    )
    response["Cache-Control"] = "no-store"
    return response


@api_view(["POST"])
@permission_classes([AllowAny])
def local_demo_auth(request):
    if not settings.DEBUG or not settings.LOCAL_DEMO_LOGIN:
        raise Http404
    if not _is_loopback_request(request):
        raise Http404

    username = str(request.data.get("username") or "").strip()
    password = request.data.get("password")
    if (
        username != settings.LOCAL_DEMO_USERNAME
        or not isinstance(password, str)
        or not password
    ):
        return _invalid_credentials_response()

    user = authenticate(request=request, username=username, password=password)
    if (
        user is None
        or not user.is_active
        or user.is_staff
        or user.is_superuser
    ):
        return _invalid_credentials_response()

    refresh = RefreshToken.for_user(user)
    response = Response(
        {
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": {
                "id": user.id,
                "username": user.username,
                "nickname": user.first_name,
                "email": user.email,
            },
        }
    )
    response["Cache-Control"] = "no-store"
    return response
